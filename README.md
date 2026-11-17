# Morpheus Distributor: buying a share of the daily emission with a token transfer

    forge test --match-path test/YieldSplitAttack.t.sol -vv

Mainnet fork at block 26430567. Targets the live Distributor
0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A and the USDT DepositPool
0x3B51989212BEdaB926794D6bf8e9E991218cf116.

## What the three tests show

`test_baselineShare`: a normal period credits the USDT pool 2.540129845812201032 MOR.

`test_control_noStakeNoProfit`: with the same 450 USDT donation but no stake in the pool, the
allocation still moves (1,419.13 MOR) and the attacker claims exactly 0. The donation only pays
someone who owns the pool.

`test_yieldSplitAttack`: 200,000 USDT staked with a one-year claim lock gives a 1.88x multiplier and
91.1% of the pool. A 450 USDT aToken donation on top makes the pool earn 1,434.40 MOR that period.
The attacker claims 1,306.83 MOR, about $914.78 at $0.70, against $450 spent.

## Attacker P&L after gas

One cycle is stake, approve, aToken transfer, distributeRewards and claim, roughly 810k gas. At
30 gwei and ETH at $3,000 that is 0.0243 ETH, so about $72.90. Net is $391.88 per distribution, and
$440.48 at 10 gwei. The stake itself comes back after the 7-day withdraw lock.

## Who pays for it

The donation lifts measured yield from $463.93 to $921.42 a day, so every honest pool's slice of the
2,856.66 MOR daily emission shrinks:

    pool         before                    after                     loss
    stETH        2,444.11 MOR ($1,710.87)  1,230.59 MOR ($861.42)    1,213.51 MOR ($849.46)
    USDC           369.45 MOR   ($258.62)    186.02 MOR ($130.21)      183.43 MOR ($128.40)
    wETH/wBTC       43.10 MOR    ($30.17)     21.70 MOR  ($15.19)       21.40 MOR  ($14.98)

That is 1,418.35 MOR, about $992.84, moved in one day. Per depositor it follows virtual weight: 1% of
the stETH pool's weight is about $8.49 a day.

## Two things the test does that the chain does differently

The aToken position is written straight into the aToken proxy's packed scaled-balance slot (mapping
slot 52, Aave index about 1.1833e27). Calling AavePool.supply() in the fork dies with
EvmError: NotActivated, an EVM-spec problem in the fork rather than in Aave. On mainnet the attacker
supplies USDT to Aave and gets the same aUSDT. USDT is seeded at slot 2 for the same reason: the
attacker needs capital and the fork has none.

The distribution needs block.timestamp past lastCalculated plus 86,400, which is 13.7 hours after the
fork block. A forked ChainLink round keeps a frozen updatedAt, so the consumer would return 0 and the
call would revert. The test rewrites the six feed timestamps to the simulated block time with
vm.mockCall and leaves the answers alone, which is what those feeds return at that moment.

## Measured vs modelled

Everything above is measured in the PoC, except this paragraph. The $545/day figure for a 100% pool
share is arithmetic, not demonstrated. The 10.7x lock variant would net $537.77/day but nothing is
claimable before 2040-01-26, because _claim requires block.timestamp past claimLockEnd. Neither is
used as the headline number.
