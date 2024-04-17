// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


/**
 * @title  Official GEM contract
 * @author The gembox crew | https://www.gembox.wtf | X: https://twitter.com/gembox_wtf | Telegram: https://t.me/gembox_wtf
 */
contract GemToken is ERC20Burnable, Ownable {
    uint256 constant public DENOMINATOR = 100_00;
    uint8 constant public BUY_SELL_TAX = 5;
    address public auctionHouse;
    bool public applyTaxOnTransfer = false;
    uint256 public minimumTokensBeforeSwap;
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) private _isExcludedFromFee;
    bool private _swapping = false;


    /**
     * @notice Initialize the GEM contract.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _initialOwner,
        uint256 _initialSupply,
        address _uniswapRouterAddress,
        address _auctionHouseAddress
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        auctionHouse = _auctionHouseAddress;
        minimumTokensBeforeSwap = (_initialSupply) / (DENOMINATOR * 100);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_uniswapRouterAddress);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        addAutomatedMarketMakerPair(_uniswapV2Pair);

        _isExcludedFromFee[_initialOwner] = true;
        _isExcludedFromFee[address(this)] = true;
        _mint(msg.sender, _initialSupply);
    }


    /**
     * @notice Add a pool for calculating taxes
     */
    function addAutomatedMarketMakerPair(address pair) public {
        automatedMarketMakerPairs[pair] = true;
    }


    function _update(address from, address to, uint256 amount) internal virtual override {
        if (amount == 0) {
            super._update(from, to, 0);
            return;
        }

        bool isBuyFromLp = automatedMarketMakerPairs[from];
        bool isSellToLp = automatedMarketMakerPairs[to];
        uint8 totalFee = _adjustTaxes(isBuyFromLp, isSellToLp);

        bool canSwap = balanceOf(address(this)) >= minimumTokensBeforeSwap;
        if (canSwap && !_swapping && totalFee > 0 && isSellToLp) {
            _swapping = true;
            _swapAndSend();
            _swapping = false;
        }

        bool takeFee = !_swapping;

        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        if (takeFee && totalFee > 0) {
            uint256 fee = (amount * totalFee) / 100;
            amount = amount - fee;
            super._update(from, address(this), fee);
        }

        super._update(from, to, amount);
    }

    function _adjustTaxes(bool isBuyFromLp, bool isSelltoLp) private view returns (uint8) {
        return (isBuyFromLp || isSelltoLp || applyTaxOnTransfer) ? BUY_SELL_TAX : 0;
    }

    function _swapAndSend() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 initialETHBalance = address(this).balance;
        uint256 amountToSwap = contractBalance;

        _swapTokensForETH(amountToSwap);

        uint256 ethBalanceAfterSwap = address(this).balance - initialETHBalance;
        Address.sendValue(payable(auctionHouse), ethBalanceAfterSwap);
    }

    function _swapTokensForETH(uint256 tokenAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            1, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    receive() external payable {}
}