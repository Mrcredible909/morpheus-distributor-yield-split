# Morpheus Distributor: emission split is purchasable with a donation

`forge test --match-path test/YieldSplitAttack.t.sol -vv`

Forks Ethereum mainnet at block 26430567 against the live Distributor
0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A and the USDT DepositPool
0x3B51989212BEdaB926794D6bf8e9E991218cf116.

- `test_baselineShare`    the USDT pool earns 2.540129845812201032 MOR in a normal period.
- `test_yieldSplitAttack` a 450 USDT aToken donation makes the same pool earn 1,434.40 MOR;
  the attacker (200,000 USDT staked with a 1-year claim lock, 1.88x multiplier, 91% of the pool)
  claims 1,306.83 MOR = $914.78 against a $450 cost, i.e. +$464.78 in one distribution.
