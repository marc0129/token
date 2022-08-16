const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

const addressBook = process.env.ADDRESS_BOOK || '';

async function main() {
    const AddLiquidity = await ethers.getContractFactory("AddLiquidity");
    const addliquidity = await upgrades.deployProxy(AddLiquidity);
    await addliquidity.deployed();
    await addliquidity.setAddressBook(addressBook);
    const AddressBook = await ethers.getContractFactory("AddressBook");
    const addressbook = AddressBook.attach(addressBook);
    await addressbook.set("addLiquidity", addliquidity.address);
    console.log("AddLiquidity proxy deployed to:", addliquidity.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
