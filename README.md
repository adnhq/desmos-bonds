# Desmos Documentation

Desmos uses ERC1155 NFTs to represent bonds, each with their own unique specifications and supply. 

## Workflow

1. **Issuance of Bonds:** An issuer with the `ISSUER_ROLE` can create new bond types using the `issueBonds` function. They specify the bond parameters such as par value AKA the face value, price, coupon rate scaled by 10, maturity period in seconds, payout interval in seconds, and total supply. Each new bond is incrementally assigned a unique bond ID.

2. **Bond Purchase:** Any user can purchase a specified amount of bonds by providing sufficient Eth.                                               

3. **Interest Accrual:** Over time, the contract accrues interest on purchased bonds. Users can claim accrued interest using the `collectInterest` function provided that the payout interval has elapsed since the last interest payment.

4. **Bond Redemption:** Bondholders can redeem a specified amount of bonds, receiving both the par value along with any accrued interest. 

5. **Supply Management:** The issuer can update the supply of existing bonds using the `setSupply` function.

## Structs and Definitions

- `Bond`: Represents a bond type with parameters such as par value, price, coupon rate, maturity period, payout interval, and supply.

- `Purchase`: Records the details of a bond purchase, including the purchased amount and last interest payment unix timestamp.

## Transfers

The Desmos NFTs can not be transferred to another address once minted. They are minted upon purchase and burned upon redemption. The transfer functions in the contract have been overriden to disable any transfer between accounts. 

## Minimum Reserve Ratio

Desmos enforces a minimum reserve ratio of 50%. This means that the admin cannot withdraw more than 50% of the Ether currently accumulated in the contract from bond purchases. This is done to ensure that a sufficient reserve is maintained to cover potential bond redemptions and interest payments.

## Roles

- `ISSUER_ROLE`: Addresses with the ISSUER_ROLE can create new bonds and adjust the supply of existing bonds.

- `DEFAULT_ADMIN_ROLE`: The address with the DEFAULT_ADMIN_ROLE has update the base URI, treasury address and can withdraw Ether from the contract upto the reserve limit.

## Disclaimer

In case of reuse, please perform your own tests to ensure security of the code. 
