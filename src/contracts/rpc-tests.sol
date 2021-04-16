pragma solidity >=0.5.15 <0.6.0;

import "ds-test/test.sol";
import "./addresses.sol";
import "./interfaces.sol";

contract Hevm {
    function warp(uint256) public;
    function store(address, bytes32, bytes32) public;
}

contract TinlakeRPCTests is DSTest, TinlakeAddresses {
    Hevm public hevm;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // cheat: give testContract permissions on root contract by overriding storage
        // storage slot for permissions => keccak256(key, mapslot) (mapslot = 0)
        hevm.store(ROOT, keccak256(abi.encode(address(this), uint(0))), bytes32(uint(1)));
    }

    function testBasicRelyReserve() public {
        RootLike(ROOT).relyContract(RESERVE, address(this));
        assertEq(AuthLike(RESERVE).wards(address(this)), 1);
    }
}
