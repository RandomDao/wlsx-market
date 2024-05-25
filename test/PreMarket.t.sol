// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "../src/PreMarket.sol";
import "../src/Project.sol";
import "./BaseERC20.sol";
import "lib/erc6551/src/examples/simple/ERC6551Account.sol";
import "lib/erc6551/src/ERC6551Registry.sol";

contract PreMarketTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public implementation;

    Project project;
    PreMarket preMarket;
    BaseERC20 token;
    address buyer;
    address seller;

    function setUp() public {
        registry = new ERC6551Registry();
        implementation = new ERC6551Account();

        token = new BaseERC20("EIGEN", "EIGEN");
        project = new Project(address(registry), payable(address(implementation)));
        preMarket = new PreMarket(address(project));
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        token.transfer(seller, 100);
        vm.deal(seller, 100);
        vm.deal(buyer, 100);
        project.addPreProject("EIGEN", address(token), block.timestamp + 1 hours, block.timestamp + 2 hours, 0);
    }

    function testAddOrder() public {
        vm.prank(buyer);
        preMarket.addOrder{value: 100}(0, 100, 100, 0, 0);
        PreMarket.PreOrder[] memory list = preMarket.preOrdersList(0, 0);
        assertEq(list.length, 1);

        vm.prank(seller);
        preMarket.matchOrder{value: 100}(0, 100);
        PreMarket.PreOrder[] memory empty = preMarket.preOrdersList(0, 0);
        assertEq(empty.length, 0);
    }
}
