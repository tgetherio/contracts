// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MOCKFundContract{

    function fundUpkeep(address _contractAddress) external payable returns (bool) {
        if (msg.value <= 0 || _contractAddress!=msg.sender){ 
            return false;
        }else {
        return true;
        }
    }

}