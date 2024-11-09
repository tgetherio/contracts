// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC677 {
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract tgetherFundTest {
    IERC677 public LINK;
    address upkeepRegistrar;
    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    // Initialize the LINK token address and upkeep registrar address
    constructor() {
        LINK = IERC677(0xb1D4538B4571d411F07960EF2838Ce337FE1E80E); // LINK token address on Arbitrum testnet
        upkeepRegistrar = 0x8194399B3f11fcA2E8cCEfc4c9A658c61B8Bf412;
        owner = msg.sender;
    }

    mapping(address => uint256) upkeeps;

    /**
     * @dev Fund the upkeep of a contract by transferring 0.02 LINK from the caller.
     * @param _contractAddress The address of the contract to fund
     * @return bool indicating whether the operation was successful
     */
    function fundUpkeep(address _contractAddress) external payable returns (bool) {
        require(upkeeps[_contractAddress] > 0, "No upkeep set for this contract");

        uint256 amount = 0.02 * 10**18; // 0.02 LINK in wei

        // Transfer 0.02 LINK from the caller to this contract
        require(LINK.transferFrom(tx.origin, address(this), amount), "LINK transfer failed");

        // Fund the upkeep using transferAndCall (ERC677 function)
        LINK.transferAndCall(upkeepRegistrar, amount, abi.encode(upkeeps[_contractAddress]));
        return true;
    }

    function updateRegistrar(address _address) external onlyOwner {
        upkeepRegistrar = _address;
    }

    function setUpkeeps(address _address, uint256 _upkeep) external onlyOwner {
        upkeeps[_address] = _upkeep;
    }

    function checkBal() external view returns (uint256) {
        return LINK.balanceOf(address(this));
    }
}
