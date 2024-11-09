// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC677 {
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function balanceOf(address account) external view returns (uint256);
}

interface ISushiSwapRouter {
    function WETH() external pure returns (address);
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
}

contract tgetherFund {
    ISushiSwapRouter public sushiSwapRouter;
    IERC677 public LINK;
    
    address upkeepRegistrar;
    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    // Initialize the SushiSwap Router and LINK token addresses
    constructor() {
        sushiSwapRouter = ISushiSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // SushiSwap router address on Arbitrum
        LINK = IERC677(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4); // LINK token address
        upkeepRegistrar = 0x37D9dC70bfcd8BC77Ec2858836B923c560E891D1;
        owner = msg.sender;
    }
    mapping(address => uint256) upkeeps;

    // Function to perform the swap after approval

    // FUND UPKEEP IS NOT MEANT TO BE CALLED DIRECTLY BY THE USER AND IS NOT MEANT FOR LARGE TRANSACTIONS
    // THIS FUNCTION DOES NOT HAVE PROPER SLIPPAGE HANDLING AND IS ONLY MEANT TO BE USED FOR SMALL TRANSACTIONS

    /*
     * @dev Fund the upkeep of a contract by swapping ETH for LINK and transferring it to the upkeep contract
     * @DEV IMPORTANT: This function is not meant to be called directly by the user and is not meant for large transactions
     * @param _contractAddress The address of the contract to fund
     * @return bool
     */
    function fundUpkeep(address _contractAddress) external payable returns (bool) {
        require(msg.value > 0, "Insufficient ETH sent");
        require(upkeeps[_contractAddress] > 0 );

        address[] memory path = new address[](2);
        path[0] = sushiSwapRouter.WETH();
        path[1] = address(LINK);


        // IMPORTANT here minum link is set to 0 because we will only be transfering small amounts eth (<$2) 
        // if transfering large amounts set value higher to account for slippage 
        try sushiSwapRouter.swapExactETHForTokens{ value: msg.value }(
            0, // Set minimum LINK received to 0, adjust if needed
            path,
            address(this),
            block.timestamp + 60 // Add buffer time
        ) {}catch Error(string memory reason) {
            // Catch revert reason and re-throw with detailed error message
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch {
            // Fallback for unknown errors
            revert("Swap failed: Unknown error");
        }
        
        // Transfer LINK to upkeep contract
        uint256 linkBalance = LINK.balanceOf(address(this));
        require(linkBalance > 0, "No LINK received from swap");

        // Fund the upkeep job using transferAndCall (ERC677 function)
        LINK.transferAndCall(upkeepRegistrar, linkBalance, abi.encode(upkeeps[_contractAddress]));
        return true;
    }

    function checkBal() external view returns (uint256){
        return LINK.balanceOf(address(this));

    }

    function updateRegistrar(address _address) external onlyOwner{
        upkeepRegistrar= _address;

    }
    function setUpkeeps(address _address, uint256 _upkeep) external onlyOwner{
        upkeeps[_address]= _upkeep;

    }

}
