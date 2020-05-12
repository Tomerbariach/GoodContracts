pragma solidity 0.5.4;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "@daostack/arc/contracts/controller/Avatar.sol";
import "../../contracts/dao/schemes/FeelessScheme.sol";
import "../../contracts/dao/schemes/ActivePeriod.sol";
import "./GoodReserveCDai.sol";


interface StakingContract {
    function collectUBIInterest(address recipient)
        external
        returns (uint256, uint256, uint256, uint32);
}


/**
 * @title GoodFundManager contract that transfer interest from the staking contract
 * to the reserve contract and transfer the return mintable tokens to the staking
 * contract
 * cDAI support only
 */
contract GoodFundManager is FeelessScheme, ActivePeriod {
    using SafeMath for uint256;

    ERC20 cDai;
    GoodReserveCDai public reserve;
    address public bridgeContract;
    address public homeAvatar;

    // // tracking the daily withdraws and the actual amount
    // // at the begining of the trading day.
    // mapping (uint256 => Funds) public dailyFunds;

    event FundsTransferred(
        address indexed caller,
        address indexed staking,
        address indexed reserve,
        uint256 cDAIinterestEarned,
        uint256 cDAIinterestDonated,
        uint256 gdInterest,
        uint256 gdUBI
    );

    modifier reserveHasInitialized {
        require(address(reserve) != address(0), "reserve has not initialized");
        _;
    }

    constructor(
        address _cDai,
        Avatar _avatar,
        Identity _identity,
        address _bridgeContract,
        address _homeAvatar
    ) public FeelessScheme(_identity, _avatar) ActivePeriod(now, now * 2) {
        cDai = ERC20(_cDai);
        bridgeContract = _bridgeContracts;
        homeAvatar = _homeAvatar;
        start();
    }

    /* @dev Start function. Adds this contract to identity as a feeless scheme.
     * Can only be called if scheme is registered
     */
    function start() public onlyRegistered {
        addRights();
        super.start();
    }

    /**
     * @dev sets the reserve
     * @param _reserve contract
     */
    function setReserve(GoodReserveCDai _reserve) public onlyAvatar {
        reserve = _reserve;
    }

    /**
     * @dev sets the token bridge address on mainnet and the recipient of minted UBI (avatar on sidechain)
     * @param _bridgeContract address
     * @param _avatar address
     */
    function setBridgeAndHomeAvatar(address _bridgeContract, address _avatar)
        public
        onlyAvatar
    {
        bridgeContract = _bridgeContract;
        homeAvatar = _avatar;
    }

    /**
     * @dev collects ubi interest in cdai from from a given staking and transfer it to
     * the reserve contract. then transfer the given gd which recieved from the reserve
     * back to the staking contract.
     * @param staking contract that implements `collectUBIInterest` and transfer cdai to
     * a given address.
     */
    function transferInterest(StakingContract staking)
        public
        requireActive
        onlyRegistered
        reserveHasInitialized
    {
        // cdai balance of the reserve contract
        uint256 currentBalance = cDai.balanceOf(address(reserve));
        // collects the interest from the staking contract and transfer it directly to the reserve contract
        //collectUBIInterest returns (cdaigains, daigains, precission loss, donation ratio)
        (, , , uint32 donationRatio) = staking.collectUBIInterest(
            address(reserve)
        );

        // finds the actual transferred cdai
        uint256 actualCDaiGains = cDai.balanceOf(address(reserve)).sub(
            currentBalance
        );
        if (actualCDaiGains > 0) {
            uint256 interestDonated = interest.mul(donationRatio).div(1e6);
            uint256 afterDonation = interest.sub(interestDonated);
            // mints gd while the interest amount is equal to the transferred amount
            (uint256 gdInterest, uint256 gdUBI) = reserve.mintInterestAndUBI(
                cDai,
                actualCDaiGains,
                afterDonation
            );
            // transfers the minted tokens to the given staking contract
            GoodDollar token = GoodDollar(address(avatar.nativeToken()));
            token.transfer(address(staking), gdInterest);
            //transfer ubi to avatar on sidechain via bridge
            token.transferAndCall(
                tokenBridge,
                gdUBI,
                bytes32(uint256(homeAvatar))
            );
            emit FundsTransferred(
                msg.sender,
                address(staking),
                address(reserve),
                actualCDaiGains,
                donated,
                gdInterest,
                gdUBI
            );
        }
    }

    /**
     * @dev making the contract inactive after it has transferred funds to `_avatar`
     * only the avatar can destroy the contract.
     * @param _avatar destination avatar address for funds
     */
    function end(Avatar _avatar) public onlyAvatar {
        uint256 remainingCDaiReserve = cDai.balanceOf(address(this));
        if (remainingCDaiReserve > 0) {
            cDai.transfer(address(_avatar), remainingCDaiReserve);
        }
        GoodDollar token = GoodDollar(address(avatar.nativeToken()));
        uint256 remainingGDReserve = token.balanceOf(address(this));
        if (remainingGDReserve > 0) {
            token.transfer(address(_avatar), remainingGDReserve);
        }
        super.internalEnd(_avatar);
    }
}