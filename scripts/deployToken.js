const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

const addressBook = process.env.ADDRESS_BOOK || '';

async function main() {
    const AddressBook = await ethers.getContractFactory("AddressBook");
    const addressbook = await AddressBook.attach(addressBook);
    // deploy token
    const Token = await ethers.getContractFactory("Token");
    const token = await upgrades.deployProxy(Token);
    await token.deployed();
    await token.setAddressBook(addressBook);
    await addressbook.set('token', token.address);
    console.log("Token proxy deployed to:", token.address);
    // deploy pool
    const Pool = await ethers.getContractFactory("Pool");
    const pool = await upgrades.deployProxy(Pool);
    await pool.deployed();
    await pool.setAddressBook(addressBook);
    await addressbook.set('pool', pool.address);
    console.log("Pool proxy deployed to:", pool.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
