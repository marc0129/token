const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

const addressBook = process.env.ADDRESS_BOOK || '';

async function main() {
    const AutoCompoundV2 = await ethers.getContractFactory("AutoCompoundV2");
    const autocompound = await upgrades.deployProxy(AutoCompoundV2);
    await autocompound.deployed();
    await autocompound.setAddressBook(addressBook);
    const AddressBook = await ethers.getContractFactory("AddressBook");
    const addressbook = await AddressBook.attach(addressBook);
    await addressbook.set('autocompound', autocompound.address);
    console.log("AutoCompoundV2 proxy deployed to:", autocompound.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
