// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SafeHarness {
    address internal constant DELAY = 0x2222222222222222222222222222222222222222;
    address internal constant ROLES = 0x6666666666666666666666666666666666666666;

    function isModuleEnabled(address module) external pure returns (bool) {
        return module == DELAY || module == ROLES;
    }

    function getModulesPaginated(address, uint256)
        external
        pure
        returns (address[] memory modules, address next)
    {
        modules = new address[](2);
        modules[0] = DELAY;
        modules[1] = ROLES;
        next = address(0x1);
    }
}

// Runtime is installed at the official Delay mastercopy address. Calls arrive
// through the exact Zodiac minimal-proxy runtime and therefore use proxy slots.
contract DelayHarness {
    address public avatar;
    address public target;
    address public owner;
    address public expectedOwner;

    function isModuleEnabled(address module) external view returns (bool) {
        return module == expectedOwner;
    }
}

contract RolesHarness {
    address public avatar;
    address public target;
    address public owner;
}

contract TokenHarness {
    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
}
