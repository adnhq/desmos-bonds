// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20; 

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Desmos NFT Bonds
 * @author adnhq (@Hawkyne)
 * @notice Desmos uses NFTs to represent bonds with different specifications and supplies. 
 */
contract Desmos is ERC1155, AccessControl {
    /**
     * @dev Incorrect amount of Ether provided for bond purchase
     */
    error IncorrectEthAmountProvided();   

    /**
     * @dev One or more zero value argument provided.
     */    
    error InvalidArgumentProvided();

    /**
     * @dev Transaction would exceed the current minimum Eth reserve required in the contract.
     */    
    error ExceedsMinimumReserve();
    
    /**
     * @dev The provided bondId does not correspond to an issued bond.
     */    
    error UnissuedBondProvided();

    /**
     * @dev Amount provided is greater than the caller's balance of bonds.
     */    
    error AmountExceedsBalance();
    /**
     * @dev Bonds can not be transferred to a different address.
     */    
    error BondsAreNonTransferrable();

    /**
     * @dev Accrued interest amount is zero for queried bond purchase.
     */  
    error InsufficientInterestAccrued();

    /**
     * @dev Could not transfer Ether to target address.
     */  
    error EthTransferFailed();
    
    struct Bond {
        uint parValue;                            // Base amount of Eth redeemable upon maturity.
        uint price;                               // Amount of Eth required to purchase one bond.
        uint couponRate;                          // Annual interest percentage scaled by 10. ie. 5% = 50, 3.5% = 35
        uint maturityPeriod;                      // Maturity period in seconds.
        uint payoutInterval;                      // Interval period between payouts in seconds.
        uint supply;                              // Current available supply for the bond.
    }

    struct Purchase {
        uint amount;                              // Amount of bonds purchased.
        uint lastInterestPaymentTimestamp;        // Unix timestamp of last interest payout.
    }

    bytes32 public constant ISSUER_ROLE = 0x114e74f6ea3bd819998f78687bfcb11b140da08e9b7d222fa9c1f1ba1f2aa122; // keccak256("ISSUER_ROLE")
    
    uint public constant MIN_RESERVE_RATIO = 50;  // Minimum 50% of the current total funds should stay in the contract at all times.

    uint public totalFunds;                       // Total amount of Eth currently in the contract that had been accumulated from bond purchases.
    uint private _counter;                        // Counter for issuing new bonds. Bonds start being issued from bondId 0.

    address public treasury;                      // Treasury wallet address.

    mapping(uint bondId => Bond bond) public bonds;
    mapping(address bondholder => mapping(uint bondId => Purchase[] purchaseList)) public purchases;

    event BondsIssued(uint bondId, address indexed issuer);
    event BondsPurchased(uint bondId, uint amount, uint purchaseIndex, uint purchaseTimestamp, address indexed buyer);
    event InterestCollected(uint bondId, uint purchaseIndex, uint ethCollected, uint collectionTimestamp, address indexed buyer);
    event BondsRedeemed(uint bondId, uint purchaseIndex, uint amount, uint ethReceived, uint redeemTimestamp, address indexed buyer);
    event BondSupplyUpdated(uint bondId, uint oldSupply, uint newSupply, address indexed issuer);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event FundsWithdrawn(uint amountEth, uint timestamp, address indexed admin);

    /**
     * @dev Initializes `baseURI` and grants `DEFAULT_ADMIN_ROLE` and `ISSUER_ROLE` to the deployer.
     */
    constructor(string memory baseURI) ERC1155(baseURI) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ISSUER_ROLE, msg.sender);
    }

    // To receive Ether
    receive() external payable {}

    /// Functions with restricted access are marked as payable to save some gas based on the assumption that the functions will be called appropriately. 


    /**
     * @notice Issues specified amount of a new bond.
     * @param _parValue Par value for the bond. 
     * @param _price Price of each bond.
     * @param _couponRate Annual interest rate percentage of the bond.
     * @param _maturityPeriod Maturity period of the bond in seconds.
     * @param _supply Total supply for the bond.
     * 
     * Requirements-
     * 
     * - caller must have `ISSUER_ROLE`.
     * - value of arguments must be non-zero.
     */
    function issueBonds(
        uint _parValue, 
        uint _price, 
        uint _couponRate, 
        uint _maturityPeriod, 
        uint _payoutInterval, 
        uint _supply
    ) external payable 
    onlyRole(ISSUER_ROLE) 
    {
        if(_parValue == 0 || _price == 0 || _couponRate == 0 || _maturityPeriod == 0 || _payoutInterval == 0 || _supply == 0) 
            _revert(InvalidArgumentProvided.selector);

        bonds[_counter] = Bond({
            parValue: _parValue,
            price: _price,
            couponRate: _couponRate,
            maturityPeriod: _maturityPeriod,
            payoutInterval: _payoutInterval,
            supply: _supply
        });

        unchecked {
            emit BondsIssued(_counter++, msg.sender);
        }
    }   
    
    /**
     * @notice Updates supply for a bond.
     * @param bondId Id of bond to update.
     * @param newSupply Supply amount for the bond to be set to.
     * 
     * Requirements-
     * 
     * - caller must have `ISSUER_ROLE`.
     * - `bondId` must have been issued.
     */
    function setSupply(uint bondId, uint newSupply) external payable onlyRole(ISSUER_ROLE) {
        if(bondId >= _counter) _revert(UnissuedBondProvided.selector);

        uint oldSupply = bonds[bondId].supply;
        bonds[bondId].supply = newSupply;

        emit BondSupplyUpdated(bondId, oldSupply, newSupply, msg.sender);
    }

    /**
     * @notice Purchase specified amount of a bond.
     * @param bondId Id of bond to purchase.
     * @param _amount Amount of bonds to purchase.
     * 
     * Requirements-
     * 
     * - `bondId` must have been issued.
     * - correct amount of ether should have been sent for the purchase.
     */
    function purchaseBonds(uint bondId, uint _amount) external payable {
        if(bondId >= _counter) _revert(UnissuedBondProvided.selector);
        Bond storage bond = bonds[bondId];

        if(msg.value != bond.price * _amount) _revert(IncorrectEthAmountProvided.selector);
        bond.supply -= _amount; // will revert in case of underflow

        unchecked {
            // overflow is unrealistic
            totalFunds += msg.value;
        }

        Purchase[] storage userPurchases = purchases[msg.sender][bondId];

        userPurchases.push(Purchase({
            amount: _amount,
            lastInterestPaymentTimestamp: block.timestamp
        }));

        _mint(msg.sender, bondId, _amount, "");

        unchecked {
            emit BondsPurchased(bondId, _amount, userPurchases.length - 1, block.timestamp, msg.sender);
        }
    }
    
    /**
     * @notice Collects interest for a bond.
     * @param bondId Id of the bond to claim interest for.
     * @param purchaseIndex Index of bond purchase to collect interest for.
     * 
     * Requirements-
     *
     * - purchase must have accrued interest.
     */
    function collectInterest(uint bondId, uint purchaseIndex) external {
        Bond memory bond = bonds[bondId];
        Purchase memory purchase = purchases[msg.sender][bondId][purchaseIndex];

        (uint accruedInterest, uint updatedTimestamp) = _getInterest(bond, purchase);
        
        if(accruedInterest == 0) _revert(InsufficientInterestAccrued.selector);

        purchases[msg.sender][bondId][purchaseIndex].lastInterestPaymentTimestamp = updatedTimestamp; 

        _transferEth(msg.sender, accruedInterest);

        emit InterestCollected(bondId, purchaseIndex, accruedInterest, block.timestamp, msg.sender);
    }

    /**
     * @notice Redeems specified amount of a bond.
     * @param bondId Id of the bonds to redeem.
     * @param _amount Amount of bonds to be redeemed.
     * @param purchaseIndex Purchase to redeem bonds from.
     * 
     * Requirements-
     * 
     * - caller must own at least `_amount` of bonds.
     *
     * Any outstanding interest on the specified purchase is also transferred 
     * along with the par value of the bonds.
     */
    function redeemBond(uint bondId, uint _amount, uint purchaseIndex) external {
        Purchase memory purchase = purchases[msg.sender][bondId][purchaseIndex];
        if(_amount > purchase.amount) _revert(AmountExceedsBalance.selector);

        Bond memory bond = bonds[bondId];  
        
        (uint accruedInterest, uint updatedTimestamp) = _getInterest(bond, purchase);
        uint totalPrincipal = bond.parValue * _amount;
        uint amountEth = totalPrincipal + accruedInterest;

        purchases[msg.sender][bondId][purchaseIndex].lastInterestPaymentTimestamp = updatedTimestamp;

        unchecked {
            purchases[msg.sender][bondId][purchaseIndex].amount -= _amount; 
            totalFunds -= totalPrincipal;
        }

        _burn(msg.sender, bondId, _amount);
        _transferEth(msg.sender, amountEth);

        emit BondsRedeemed(bondId, purchaseIndex, _amount, amountEth, block.timestamp, msg.sender);
    }

    // ============================================================
    //                    DEFAULT_ADMIN ACCESS
    // ============================================================

    /**
     * @notice Set base URI for collection.
     * @param baseURI base URI of the collection.
     *
     * Requirements-
     *
     * - caller must have the `DEFAULT_ADMIN_ROLE`.
     */
    function setBaseURI(string calldata baseURI) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(baseURI);
    }

    /**
     * @notice Updates treasury address.
     * @param newTreasury Address of new treasury wallet.
     *
     * Requirements-
     *
     * - caller must have the `DEFAULT_ADMIN_ROLE`.
     * - `newTreasury` should not be the zero address.
     */
    function setTreasury(address newTreasury) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        if(newTreasury == address(0)) _revert(InvalidArgumentProvided.selector);
        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }   

    /**
     * @notice Transfers funds to treasury.
     * @param amountEth Amount of ether to transfer.
     *
     * Requirements-
     *
     * - caller must have DEFAULT_ADMIN_ROLE.
     *
     */
    function withdrawFunds(uint amountEth) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        if(address(this).balance - amountEth < getCurrentReserve()) _revert(ExceedsMinimumReserve.selector);

        _transferEth(treasury, amountEth);

        emit FundsWithdrawn(amountEth, block.timestamp, msg.sender);
    }

    // ============================================================
    //                      GETTER FUNCTIONS
    // ============================================================

    /**
     * @notice Returns the claimable accrued interest on a specific purchase of bonds.
     * @param bondholder Address of the bondholder.
     * @param bondId Id of the bond.
     * @param purchaseIndex Index of bond purchase to calculate interest for.
     * @return accruedInterest The amount of accrued claimable interest in Eth.
     */
    function getAccruedInterest(address bondholder, uint bondId, uint purchaseIndex) external view returns (uint accruedInterest) {
        Bond memory bond = bonds[bondId];
        Purchase memory purchase = purchases[bondholder][bondId][purchaseIndex];

        (accruedInterest, ) = _getInterest(bond, purchase);
    }
    
    /**
     * @notice Returns claimable accrued interests for all the purchases of `bondholder` for the specified `bondId`.
     * @param bondholder Address of the bondholder.
     * @param bondId Id of the bond.
     * @return accruedInterests Array of interests for all purchases.
     */
    function getAccruedInterestsForAllPurchases(address bondholder, uint bondId) external view returns (uint[] memory accruedInterests) {
        Bond memory bond = bonds[bondId];
        Purchase[] memory userPurchases = purchases[bondholder][bondId];
        uint length = userPurchases.length;
        accruedInterests = new uint[](length);

        unchecked {
            for(uint i; i < length; ++i)
                (accruedInterests[i], ) = _getInterest(bond, userPurchases[i]);
        }
    }

    /**
     * @notice Returns total number of bonds issued.
     */
    function getTotalBondsIssued() external view returns (uint) {
        return _counter;
    }

     /**
     * @notice Returns current Eth reserve.
     */
    function getCurrentReserve() public view returns (uint) {
        return totalFunds >> 1; // Divides totalFunds by 2, that is, (totalFunds * MIN_RESERVE_RATIO) / 100
    }

    // Overrides to disable bond transfers.
    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory 
    ) public virtual override {
        _revert(BondsAreNonTransferrable.selector);
    }

    function safeBatchTransferFrom(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override {
        _revert(BondsAreNonTransferrable.selector);
    }

    // Override required by solidity
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    

    // ============================================================
    //                          HELPERS
    // ============================================================

    /**
     * @dev Returns claimable accrued interest and updated payout timestamp for a specific purchase of a bond.
     */
    function _getInterest(Bond memory bond, Purchase memory purchase) private view returns (uint, uint) {
        uint payouts = (block.timestamp - purchase.lastInterestPaymentTimestamp) / bond.payoutInterval;
        if(payouts == 0) return (0, 0);
        
        uint payoutTimeElapsed = bond.payoutInterval * payouts;
        uint accruedInterestPerToken = (bond.parValue * bond.couponRate * payoutTimeElapsed) / 31536000000; // Divide by 365 days * 1000

        return (
            accruedInterestPerToken * purchase.amount, 
            purchase.lastInterestPaymentTimestamp + payoutTimeElapsed
        );
    }

    /**
     * @dev For efficient reverts.
     */
    function _revert(bytes4 errorSelector) private pure {
        assembly {
            mstore(0x00, errorSelector)
            revert(0x00, 0x04)
        }
    }

    /**
     * @dev For efficient ether transfers.
     */
    function _transferEth(address to, uint256 amountEth) private {
        bool success;

        /// @solidity memory-safe-assembly
        assembly {
            success := call(gas(), to, amountEth, 0, 0, 0, 0)
        }

        if(!success) _revert(EthTransferFailed.selector);
    }
}
