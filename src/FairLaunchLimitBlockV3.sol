// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

// IERC20
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Meme} from "./Meme.sol";
import {IFairLaunch, FairLaunchLimitBlockStruct} from "./IFairLaunch.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IUniLocker {
    function lock(
        address lpToken,
        uint256 amountOrId,
        uint256 unlockBlock
    ) external returns (uint256 id);
}

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

interface INonfungiblePositionManager {
    function WETH9() external pure returns (address);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function refundETH() external payable;
}

contract FairLaunchLimitBlockTokenV3 is
    IFairLaunch,
    Meme,
    ReentrancyGuard,
    NoDelegateCall
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public fundsToRaise = 10 ether;

    // refund command
    // before start, you can always refund
    // send 0.0002 ether to the contract address to refund all ethers
    uint256 public constant REFUND_COMMAND = 0.0002 ether;

    // claim command
    // after start, you can claim extra eth
    // send 0.0002 ether to the contract address to claim extra eth
    uint256 public constant CLAIM_COMMAND = 0.0002 ether;

    // start trading command
    // if the untilBlockNumber reached, you can start trading with this command
    // send 0.0005 ether to the contract address to start trading
    uint256 public constant START_COMMAND = 0.0005 ether;

    // mint command
    // if the untilBlockNumber reached, you can mint token with this command
    // send 0.0001 ether to the contract address to get tokens
    uint256 public constant MINT_COMMAND = 0.0001 ether;

    // minimal fund
    uint256 public constant MINIMAL_FUND = 0.0001 ether;

    // is listed on DEX
    bool public isListed;

    address public immutable uniswapPositionManager;
    address public immutable uniswapFactory;

    // fund balance
    mapping(address => uint256) public accountFunds;

    // is address minted
    mapping(address => bool) public minted;

    // total dispatch amount
    uint256 public immutable tokenTotalSupply;

    // until block number
    uint256 public immutable untilBlockNumber;

    // total ethers funded
    uint256 public totalRaised;

    // soft top cap in ETH
    uint256 public immutable softTopCap;

    // is address claimed extra eth
    mapping(address => bool) public claimed;

    // recipient must be a contract address of IUniLocker
    address public immutable locker;

    // project owner, whill receive the locked lp
    address public immutable projectOwner;

    constructor(
        address _locker,
        address _projectOwner,
        FairLaunchLimitBlockStruct memory params
    ) Meme(params.name, params.symbol, params.meta) {
        isListed = false;

        tokenTotalSupply = params.totalSupply;
        _mint(address(this), tokenTotalSupply);

        // set uniswap router
        uniswapPositionManager = params.uniswapRouter;
        uniswapFactory = params.uniswapFactory;

        meta = params.meta;

        softTopCap = params.softTopCap;

        locker = _locker;
        projectOwner = _projectOwner;
    }

    // get extra eth
    function getExtraETH(address _addr) public view returns (uint256) {
        if (totalRaised > softTopCap) {
            uint256 claimAmount = (accountFunds[_addr] *
                (totalRaised - softTopCap)) / totalRaised;
            return claimAmount;
        }
        return 0;
    }

    // estimate how many tokens you might get
    function mightGet(address account) public view returns (uint256) {
        if (totalRaised == 0) {
            return 0;
        }
        uint256 _mintAmount = (tokenTotalSupply * accountFunds[account]) /
            2 /
            totalRaised;
        return _mintAmount;
    }

    // Deposit funds to particate token sale allocation
    function participate() public payable nonReentrant {
        require(!isListed, "Token listed on DEX already");
        require(totalRaised < fundsToRaise, "Raised funds reached.");
        accountFunds[msg.sender] += msg.value;
        totalRaised += msg.value;
        emit FundEvent(msg.sender, msg.value, 0);
    }

    function claimTokens() public nonReentrant {
        require(totalRaised >= fundsToRaise, "Funds to raise not reached.");
        require(!isListed, "Token listed on DEX already.");
        require(msg.sender == tx.origin, "Can not mint to contract.");
        require(!minted[msg.sender], "Already minted.");
        require(
            accountFunds[msg.sender] > 0,
            "You did not participate the token sales."
        );

        minted[msg.sender] = true;

        uint256 mintAmount = mightGet(msg.sender);
        require(mintAmount > 0, "Mint amount is zero");
        assert(mintAmount <= tokenTotalSupply / 2);

        _transfer(address(this), msg.sender, mintAmount);
        accountFunds[msg.sender] = 0;
    }

    function createV2LP() public nonReentrant {
        require(!isListed, "Token listed already.");
        require(balanceOf(address(this)) > 0, "No token balance");
    }
}

library Math {
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 result = a;
        uint256 k = a / 2 + 1;
        while (k < result) {
            result = k;
            k = (a / k + k) / 2;
        }
        return result;
    }
}
