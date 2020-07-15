pragma solidity 0.5.4;

import "./SimpleStaking.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";


interface cERC20 {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeemUnderlying(uint256 mintAmount) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address addr) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}


/**
 * @title Staking contract that donates earned interest to the DAO
 * allowing stakers to deposit DAI/ETH
 * or withdraw their stake in DAI
 * the contracts buy cDai and can transfer the daily interest to the  DAO
 */
contract GoodCompoundStaking is SimpleStaking {




    constructor(
        address _token,
        address _iToken,
        address _fundManager,
        uint256 _blockInterval,
        Avatar _avatar,
        Identity _identity
    ) public SimpleStaking(_token, _iToken, _fundManager, _blockInterval, _avatar, _identity) {
        
    }

    /**
     * @dev stake some DAI
     * @param _amount of dai to stake
     */
    function mint(uint256 _amount) internal {
        
        cERC20 cToken = cERC20(address(iToken));
        uint res = cToken.mint(_amount);

        if (
            res > 0
        ) //cDAI returns >0 if error happened while minting. make sure no errors, if error return DAI funds
        {
            require(res == 0, "Minting cDai failed, funds returned");
        }

    }

    /**
     * @dev redeem DAI from compound 
     * @param _amount of dai to redeem
     */
    function redeem(uint256 _amount) internal {
        cERC20 cToken = cERC20(address(iToken));
        require(cToken.redeemUnderlying(_amount) == 0, "Failed to redeem cDai");

    }

    /**
     * @dev returns Dai to cDai Exchange rate.
     */
    function exchangeRate() internal view returns(uint) {
        cERC20 cToken = cERC20(address(iToken));
        return cToken.exchangeRateStored();

    }

    /**
     * @dev returns decimals of token.
     */
    function tokenDecimal() internal view returns(uint) {
        ERC20Detailed token = ERC20Detailed(address(token));
        return uint(token.decimals());
    }

    /**
     * @dev returns decimals of interest token.
     */
    function iTokenDecimal() internal view returns(uint) {
        ERC20Detailed cToken = ERC20Detailed(address(iToken));
        return uint(cToken.decimals());
    }
}