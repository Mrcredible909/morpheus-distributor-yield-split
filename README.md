# Morpheus Distributor: the daily emission split is purchasable with a donation

`forge test --match-path test/YieldSplitAttack.t.sol -vv`

Forks Ethereum mainnet at block 26430567 against the live Distributor
0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A and the USDT DepositPool
0x3B51989212BEdaB926794D6bf8e9E991218cf116.

Three tests, all passing:

- `test_baselineShare`          a normal period gives the USDT pool 2.540129845812201032 MOR.
- `test_control_noStakeNoProfit` the same 450 USDT donation bends the pool's allocation to 1,419.13 MOR,
  and an attacker with no stake in that pool claims exactly 0.
- `test_yieldSplitAttack`       200,000 USDT staked with a one-year claim lock (1.88x multiplier, 91.1%
  of the pool) plus a 450 USDT aToken donation: the pool earns 1,434.40 MOR, the attacker claims
  1,306.83 MOR = $914.78 against a $450 cost, net +$464.78 in one distribution.

## Two fork accommodations, disclosed

1. **aUSDT is seeded, not supplied through Aave.** `AavePool.supply()` reverts inside the fork with
   `EvmError: NotActivated` (an EVM-spec issue in the fork, not in Aave). The test therefore writes the
   attacker's aToken position directly at the aToken proxy's packed scaled-balance slot (mapping slot
   52, Aave liquidity index ~1.1833e27). On mainnet the attacker simply supplies USDT to Aave and
   receives the same aUSDT. USDT itself is seeded at slot 2 for the same reason: the attacker needs
   capital, and no fork has it.
2. **Oracle freshness at the simulated timestamp.** `distributeRewards` requires
   `block.timestamp > lastCalculated + 86,400`, about 13.7 hours after the fork block. A forked
   ChainLink round keeps its frozen `updatedAt`, so the consumer would return 0 and the call would
   revert. The test refreshes the six feeds' timestamps to the simulated block time with `vm.mockCall`
   while keeping their live answers unchanged, which is what the feeds return on-chain at that moment.

## What the report claims

1,431.86 MOR ($1,002.30) of one day's emission moves from the stETH and USDC depositors to the USDT
pool; the attacker keeps 1,306.83 MOR ($914.78) and pays 450 USDT. Bounded by the daily emission
(2,856.66 MOR). A 10.7x lock is available but its rewards are unclaimable until 2040, so the one-year
configuration is the best realisable one measured.
