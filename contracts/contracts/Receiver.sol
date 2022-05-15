// SPDX-License-Identifier: MIT

pragma solidity ~0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import {IStargateRouter} from "./Interfaces/IStargateRouter.sol";
import {IConnext} from "./Interfaces/IConnext.sol";

// import "./lzApp/LzApp.sol";

contract Receiver {
    using SafeERC20 for IERC20;
    using Address for address;

    /********************** VARIABLES ****************/
    ISwapRouter public immutable swapRouter;
    IStargateRouter public immutable stargateRouter;
    IConnext public immutable connext;

    uint8 public constant TYPE_SWAP_REMOTE = 1;

    address private constant USDC =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint24 public poolFee = 0;

    struct Deposit {
        bytes32 id;
        uint256 amount;
        uint256 amountUSD;
        bool risk;
    }

    mapping(bytes32 => Deposit) public deposits;
    mapping(bytes32 => bool) public inserted;
    bytes32[] public depositIDs;

    // a mapping of bytes32 to mapping of address to balances
    // mapping(bytes32 => mapping(address => uint256)) public balances;

    /********************** EVENTS *******************/

    event TransferInitiated(address asset, address from, address to);
    event Deposited(bytes32 indexed id, uint256 amount);

    constructor(
        ISwapRouter _swapRouter,
        IStargateRouter _stargateRouter,
        IConnext _connext
    ) {
        swapRouter = _swapRouter;
        stargateRouter = _stargateRouter;
        connext = _connext;
    }

    //When a deposit is done the amount and id should be stored in a struct which is then stored in the deposits mapping

    function deposit(
        bytes32 _id,
        IERC20 token,
        uint256 _amount,
        uint256 _amountUSD,
        bool risk
    ) public {
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Update Deposits and balances
        deposits[_id] = Deposit(_id, _amount, _amountUSD, risk);
        // balances[_id][msg.sender] = _amount;

        // Add id to the array of ids only if it does not exist yet
        if (!inserted[_id]) {
            depositIDs.push(_id);
            inserted[_id] = true;
        }

        emit Deposited(_id, _amountUSD);

        if (risk) {
            // Initiate a single swap.
            swap(_amount, address(token), USDC, poolFee, _amountUSD);
        }
    }

    function getDeposits(bytes32 _id) public view returns (Deposit memory) {
        return deposits[_id];
    }

    function getBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    // retrive all deposits and return an array containing deposits of each ID
    function getAllDeposits() internal view returns (Deposit[] memory) {
        Deposit[] memory result = new Deposit[](depositIDs.length);
        for (uint i = 0; i < depositIDs.length; i++) {
            result[i] = deposits[depositIDs[i]];
        }
        return result;
    }

    /// @notice Internal function to perform swaps on the UniswapV3 router.
    /// @param amountIn The amount of tokens to swap in.
    /// @param _tokenIn The token to be swapped in.
    /// @param _tokenOut The token to be swapped out.
    /// @param _poolFee The fee to be paid to the pool.
    /// @param amountOutMin The minimum amount of tokens to be swapped out.
    /// @return amountOut The amount of _tokenOut to be swapped out.

    function swap(
        uint256 amountIn,
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        // Caller must approve the contract to spend the tokens.
        // Transfer specified amount of _tokenIn to the contract.
        TransferHelper.safeTransferFrom(
            _tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        // Approve the router to spend the tokens.
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    // This function performs several swaps using the swap function above.
    // It swaps various types of tokens which are passed via a struct of type `Swap`.

    /// @notice A function to perform batch swaps.
    /// @dev This function is used to perform batch swaps using the swap function.
    /// @param _swaps A struct of type `Swap` which contains the information for the swaps to be performed.
    /// @return The amount of tokens swapped out.

    struct Swap {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint24 poolFee;
    }

    function batchSwap(Swap[] memory _swaps)
        public
        returns (uint256 amountOut)
    {
        amountOut = 0;

        for (uint256 i; i < _swaps.length; i++) {
            amountOut += swap(
                _swaps[i].amountIn,
                _swaps[i].tokenIn,
                _swaps[i].tokenOut,
                _swaps[i].poolFee,
                _swaps[i].amountOutMin
            );
        }

        return amountOut;
    }

    /**********************************************/
    /********** Bridging the Funds ****************/
    /**********************************************/

    /*********************************************/
    /*********** IStargateRouter *****************/
    /*********************************************/

    ///@notice get the swap fee.
    ///@dev This is a private function that returns the swap fee.
    /// @param _dstChainId The destination chain id.
    /// @param _toAddress The address of the destination contract.
    /// @param _transferAndCallPayload The payload for the transfer and call function.
    function _getStargateSwapFee(
        uint16 _dstChainId,
        bytes memory _toAddress,
        bytes memory _transferAndCallPayload
    ) public view returns (uint256) {
        (uint256 fee, ) = IStargateRouter(stargateRouter).quoteLayerZeroFee(
            _dstChainId,
            TYPE_SWAP_REMOTE,
            _toAddress,
            _transferAndCallPayload,
            IStargateRouter.lzTxObj(0, 0, "0x")
        );
        return fee;
    }

    // the msg.value is the "fee" that Stargate needs to pay for the cross chain message
    function stargateSend(
        uint16 _chainId,
        uint16 sPoolId,
        uint16 dPoolId,
        uint256 _amount,
        uint256 amountOutMin,
        address dstAddr,
        IERC20 token
    ) public payable {
        require(
            msg.value >=
                _getStargateSwapFee(
                    _chainId,
                    abi.encodePacked(address(this)),
                    abi.encodePacked(address(this))
                )
        );

        IERC20(token).approve(address(stargateRouter), _amount);
        IStargateRouter(stargateRouter).swap{value: msg.value}(
            _chainId, //  LayerZero chainId
            sPoolId, // source pool id
            dPoolId, // dest pool id
            payable(msg.sender), // refund adddress. extra gas (if any) is returned to this address
            _amount, // quantity to swap
            amountOutMin, // the min qty you would accept on the destination
            IStargateRouter.lzTxObj(0, 0, "0x"), // 0 additional gasLimit increase, 0 airdrop, at 0x address
            abi.encodePacked(dstAddr), // the address to send the tokens to on the destination
            bytes("") // bytes param; payload to send to the destination
        );
    }

    /*********************************************/
    /**************** Connext ********************/
    /*********************************************/

    function connextSend(
        address to,
        address asset,
        uint32 originDomain,
        uint32 destinationDomain,
        uint256 amount
    ) external payable {
        ERC20 token = ERC20(asset);
        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(connext), amount);

        bytes4 selector = bytes4(keccak256("deposit(address,uint256,address)"));

        bytes memory callData = abi.encodeWithSelector(
            selector,
            asset,
            amount,
            msg.sender
        );

        IConnext.CallParams memory callParams = IConnext.CallParams({
            to: to,
            callData: callData,
            originDomain: originDomain,
            destinationDomain: destinationDomain
        });

        IConnext.XCallArgs memory xcallArgs = IConnext.XCallArgs({
            params: callParams,
            transactingAssetId: asset,
            amount: amount
        });

        connext.xcall(xcallArgs);

        emit TransferInitiated(asset, msg.sender, to);
    }

    receive() external payable {}
}
