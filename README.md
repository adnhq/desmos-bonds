# Desmos Documentation

Desmos uses ERC1155 NFTs to represent bonds, each with their own unique attributes and total supply. 

## Workflow

1. **Issuance of Bonds:** Authorized addresses with the `ISSUER_ROLE` can create new bonds using the `issueBonds` function. At the time of issuing a new bond, the issuer would need to define bond attributes such as the par value (also known as the face value), bond price, coupon rate/interest rate (scaled by 10), maturity period (in seconds), payout interval (in seconds) and the total supply. Each new bond is incrementally assigned a unique bond ID.

2. **Purchasing Bonds:** Once issued, a user can purchase a specified amount of bonds from the available supply by providing sufficient Eth. Users can perform repeated purchases of the same bond. Each purchase of a specific bond made by a user is tracked in an array inside the `purchases` nested mapping.                                              

3. **Interest Accrual:** Over time, interest is accrued on purchased bonds at their respective coupon rates and are claimable at their respective payout frequencies. Users can claim accrued interest for a specific bond purchase using the `collectInterest` function, provided that the payout interval for the bonds have elapsed since the last interest payment.

4. **Redeeming Bonds:** Bondholders can redeem a specified amount of bonds, receiving both the par value along with any accrued interest. Early redemptions are allowed.

5. **Bond Supply:** Authorized addresses with the `ISSUER_ROLE` role can update the supply of existing bonds using the `setSupply` function.

## Structs and Definitions

- `Bond`: Represents a bond type with parameters such as par value, price, coupon rate, maturity period, payout interval, and supply.

- `Purchase`: Records the details of a bond purchase, including the purchased amount and last interest payment unix timestamp.
  
- `MIN_RESERVE_RATIO`: Percentage of the funds currently accumulated from bond purchases which has to be kept in the contract as reserve at all times. Set to 50 as constant.

## Transfers

Transfer of the Desmos bonds are prohibited. They are minted upon purchase and burned upon redemption. The ERC1155 transfer functions have been overriden to disable any transfer between accounts. 

## Minimum Reserve Ratio

Desmos enforces a minimum reserve ratio of 50%. This means that the admin cannot withdraw more than 50% of the Ether currently accumulated in the contract from bond purchases. This is done to ensure that a sufficient reserve is maintained to cover potential bond redemptions and interest payments. The current amount of Ether in the contract which has been received from bond purchases is tracked via the `totalFunds` variable. 

## Roles

- `ISSUER_ROLE`: Addresses with the ISSUER_ROLE can create new bonds and adjust the supply of existing bonds.

- `DEFAULT_ADMIN_ROLE`: The address with the DEFAULT_ADMIN_ROLE is able to update the base URI, the treasury address and can transfer Ether from the contract to the treasury.

## Disclaimer

If you intend to use or reuse the contract code, please be sure to conduct your own independent tests to verify the security of the code. 
