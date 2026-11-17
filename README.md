# Morpheus Distributor: the daily emission split is purchasable with a donation

`forge test --match-path test/YieldSplitAttack.t.sol -vv`

Forks Ethereum mainnet at block 26430567 against the live Distributor
0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A and the USDT DepositPool
0x3B51989212BEdaB926794D6bf8e9E991218cf116.

## Tests

- `test_baselineShare`           a normal period gives the USDT pool 2.540129845812201032 MOR.
- `test_control_noStakeNoProfit`  the same 450 USDT donation bends the pool's allocation to
  1,419.13 MOR, and an attacker with no stake in that pool claims exactly 0.
- `test_yieldSplitAttack`        200,000 USDT staked with a one-year claim lock (1.88x multiplier,
  91.1% of the pool) plus a 450 USDT aToken donation: the pool earns 1,434.40 MOR, the attacker
  claims 1,306.83 MOR = $914.78 against a $450 cost, net +$464.78 in one distribution.

## Attacker P&L, after gas

Measured gross/net per daily distribution: +1,306.83 MOR in, 450 USDT out, so +$464.78 at MOR $0.70.
Cost of execution per cycle: stake, approve, aToken transfer, distributeRewards and claim total about
810k gas. At 30 gwei and ETH $3,000 that is 0.0243 ETH = **$72.90**, so net after gas is about
**$391.88 per day** (~$143k per year). At 10 gwei it is $24.30 of gas and $440.48 net. The vantage is
positive under any plausible gas price; the stake itself is recoverable after the 7-day withdraw lock.

## Who loses, and how much

The donation raises total measured yield from $463.93 to $921.42 per day, so every honest pool's
share of the 2,856.66 MOR daily emission falls. Split by pool at the pinned block:

| pool | emission before | emission after | loss |
|---|---|---|---|
| stETH | 2,444.11 MOR ($1,710.87) | 1,230.59 MOR ($861.42) | 1,213.51 MOR ($849.46) |
| USDC | 369.45 MOR ($258.62) | 186.02 MOR ($130.21) | 183.43 MOR ($128.40) |
| wETH/wBTC | 43.10 MOR ($30.17) | 21.70 MOR ($15.19) | 21.40 MOR ($14.98) |
| total | | | 1,418.35 MOR ($992.84) |

Per depositor this is proportional to virtual weight: an address holding 1% of the stETH pool's
virtual weight loses about $8.49 per day. That is small per address and large in aggregate, which is
why the finding is priced on the daily diversion, not on one victim's balance.

## Two fork accommodations, disclosed

1. **aUSDT is seeded, not supplied through Aave.** `AavePool.supply()` reverts inside the fork with
   `EvmError: NotActivated` (an EVM-spec issue in the fork, not in Aave). The test writes the
   attacker's aToken position directly at the aToken proxy's packed scaled-balance slot (mapping slot
   52, Aave liquidity index ~1.1833e27). On mainnet the attacker simply supplies USDT to Aave and
   receives the same aUSDT. USDT itself is seeded at slot 2 for the same reason: the attacker needs
   capital, and no fork has it.
2. **Oracle freshness at the simulated timestamp.** `distributeRewards` requires
   `block.timestamp > lastCalculated + 86,400`, about 13.7 hours after the fork block. A forked
   ChainLink round keeps its frozen `updatedAt`, so the consumer would return 0 and the call would
   revert. The test refreshes the six feeds' timestamps to the simulated block time with `vm.mockCall`
   while keeping their live answers unchanged, which is what the feeds return on-chain at that moment.

## What is measured and what is modelled

Measured in the PoC: every number above except the next paragraph. Modelled, not demonstrated: with a
100% pool share the arithmetic optimum is about $545/day gross, and the 10.7x lock variant would net
$537.77/day but its rewards are unclaimable until 2040-01-26 because `_claim` requires
`block.timestamp > claimLockEnd`. Neither is used as the headline impact.
