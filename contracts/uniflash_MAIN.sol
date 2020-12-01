pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

interface Structs {
    struct Val {
        uint256 value;
    }

    enum ActionType {
      Deposit,   // supply tokens
      Withdraw,  // borrow tokens
      Transfer,  // transfer balance between accounts
      Buy,       // buy an amount of some token (externally)
      Sell,      // sell an amount of some token (externally)
      Trade,     // trade tokens against another account
      Liquidate, // liquidate an undercollateralized or expiring account
      Vaporize,  // use excess tokens to zero-out a completely negative account
      Call       // send arbitrary data to an address
    }

    enum AssetDenomination {
        Wei // the amount is denominated in wei
    }

    enum AssetReference {
        Delta // the amount is given as a delta from the current value
    }

    struct AssetAmount {
        bool sign; // true if positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }

    struct Info {
        address owner;  // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }

    struct Wei {
        bool sign; // true if positive
        uint256 value;
    }
}

contract DyDxPool is Structs {
    function getAccountWei(Info memory account, uint256 marketId) public view returns (Wei memory);
    function operate(Info[] memory, ActionArgs[] memory) public;
}

// File: contracts/IERC20.sol

pragma solidity ^0.5.0;


/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see `ERC20Detailed`.
 */
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

// File: contracts/dydx/DyDxFlashLoan.sol

pragma solidity ^0.5.0;




contract DyDxFlashLoan is Structs {
    DyDxPool pool = DyDxPool(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e);                      

    address payable public  WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;                 
    address payable public SAI = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    address payable public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;                  
    address payable public DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;                   
    

    mapping(address => uint256) public currencies;

    constructor() public {
        currencies[WETH] = 1;
        currencies[SAI] = 2;
        currencies[USDC] = 3;
        currencies[DAI] = 4;
    }

    modifier onlyPool() {
        require(
            msg.sender == address(pool),
            "FlashLoan: could be called by DyDx pool only"
        );
        _;
    }

    function tokenToMarketId(address token) public view returns (uint256) {
        uint256 marketId = currencies[token];
        require(marketId != 0, "FlashLoan: Unsupported token");
        return marketId - 1;
    }

    // the DyDx will call `callFunction(address sender, Info memory accountInfo, bytes memory data) public` after during `operate` call
    function flashloan(address token, uint256 amount, bytes memory data)
        internal
    {
        IERC20(token).approve(address(pool), amount + 1);
        Info[] memory infos = new Info[](1);
        ActionArgs[] memory args = new ActionArgs[](3);

        infos[0] = Info(address(this), 0);

        AssetAmount memory wamt = AssetAmount(
            false,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount
        );
        ActionArgs memory withdraw;
        withdraw.actionType = ActionType.Withdraw;
        withdraw.accountId = 0;
        withdraw.amount = wamt;
        withdraw.primaryMarketId = tokenToMarketId(token);
        withdraw.otherAddress = address(this);

        args[0] = withdraw;

        ActionArgs memory call;
        call.actionType = ActionType.Call;
        call.accountId = 0;
        call.otherAddress = address(this);
        call.data = data;

        args[1] = call;

        ActionArgs memory deposit;
        AssetAmount memory damt = AssetAmount(
            true,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount + 1
        );
        deposit.actionType = ActionType.Deposit;
        deposit.accountId = 0;
        deposit.amount = damt;
        deposit.primaryMarketId = tokenToMarketId(token);
        deposit.otherAddress = address(this);

        args[2] = deposit;

        pool.operate(infos, args);
    }
}

// File: contracts/FlashloanTaker.sol

pragma solidity ^0.5.0;

interface ERC20 {
    function totalSupply() external view returns (uint supply);
    function balanceOf(address _owner) external view returns (uint balance);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function allowance(address _owner, address _spender) external view returns (uint remaining);
    function decimals() external view returns(uint digits);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}

interface IUniV2_RouterInterface {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
}

interface IUniV2_FactoryInterface {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IWETH {
  function deposit() external payable;
  function withdraw(uint wad) external;
  function totalSupply() external view returns (uint);
  function approve(address guy, uint wad) external returns (bool);
  function transfer(address dst, uint wad) external returns (bool);
  function transferFrom(address src, address dst, uint wad) external returns (bool);
  function () external payable;
}


contract UniFlash_MAIN is DyDxFlashLoan {
    
    address payable public uniswapV2_routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;      
    address payable public uniswapV2_factoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; 
                            
    address internal null_address = 0x0000000000000000000000000000000000000000;

    address payable public contract_address = address(this);
    address public owner;
    uint256 public flashAmount;
    bytes  PERM_HINT = "PERM";

    IWETH IWETH_Contract = IWETH(WETH);
    IUniV2_RouterInterface unirouter = IUniV2_RouterInterface(uniswapV2_routerAddress);
    IUniV2_FactoryInterface unifactory = IUniV2_FactoryInterface(uniswapV2_factoryAddress);

    
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    constructor() public payable {
        owner = msg.sender;
        (bool success, ) = WETH.call.value(msg.value)("");
        require(success, "fail to get weth");
    }

    function transferOnwership(address newOwner) public onlyOwner {
        owner = newOwner; 
    }

    function threeway(address a, address b, address c, uint256 amount) internal {
        // make path 1
        address[] memory path1 = new address[](2);
            path1[0] = address(a);
            path1[1] = address(b);
            
        // make path 2
        address[] memory path2 = new address[](2);
            path2[0] = address(b);
            path2[1] = address(c);
            
        // make path 3
        address[] memory path3 = new address[](2);
            path3[0] = address(c);
            path3[1] = address(a);
        
        // approve the tokens to the unirouter
        ERC20(a).approve(uniswapV2_routerAddress, amount);
        // do the swap 
        uint256[] memory amounts1 = unirouter.swapExactTokensForTokens(amount, 1, path1, address(this), block.timestamp);

        // approve the tokens to the unirouter
        ERC20(b).approve(uniswapV2_routerAddress, amounts1[1]);
        // do the swap 
        uint256[] memory amounts2 = unirouter.swapExactTokensForTokens(amounts1[1], 1, path2, address(this), block.timestamp);

        // approve the tokens to the unirouter
        ERC20(c).approve(uniswapV2_routerAddress, amounts2[1]);
        // do the swap 
        uint256[] memory amounts3 = unirouter.swapExactTokensForTokens(amounts2[1], 1, path3, address(this), block.timestamp);

    }


    function getFlashloan(address tokenA, address tokenB, address tokenC, uint256 flashAmount) external {
        // check if uniswap has a pair 
        doPairCheck(tokenA, tokenB, tokenC);
        
        bytes memory data = abi.encode(tokenA, tokenB, tokenC, flashAmount );
        flashloan(tokenA, flashAmount ,data ); // execution goes to `callFunction`
       
        // and this point we have succefully paid the dept
    }
    
    
    function callFunction(address, /* sender */ Info calldata, /* accountInfo */bytes calldata data) external onlyPool {
        (address tokenA, address tokenB, address tokenC, uint256 flashAmount) = abi.decode(data, (address, address, address, uint256));
    
        // the dept will be automatically withdrawn from this contract at the end of execution

        threeway(tokenA, tokenB, tokenC, flashAmount);
    }

    function doPairCheck(address a, address b, address c) internal view {
        require(unifactory.getPair(a, b) != null_address, 'tokenA to tokenB is not a valid pair');
        require(unifactory.getPair(b, c) != null_address, 'tokenB to tokenC is not a valid pair');
        require(unifactory.getPair(c, a) != null_address, 'tokenC to tokenA is not a valid pair');
    }

    // 3. Withdraw ETH - input tokenAddress
    function withdrawETH() external onlyOwner{
        // 3.1 withdraw ALL ETH to msg.sender
        msg.sender.transfer(address(this).balance);
        
    }

    // 3. Withdraw Token - input tokenAddress
    function withdrawToken(address token) external onlyOwner{
       
        // 3.2 get token balance 
        uint256 balance = ERC20(token).balanceOf(contract_address);
        
        // 3.4 approve token_balance
        ERC20(token).approve(contract_address, balance); 
        
        // 3.5 withdraw ALL token to msg.sender
        ERC20(token).transfer(msg.sender, balance);
        
    }
   
    function () external payable {}
}