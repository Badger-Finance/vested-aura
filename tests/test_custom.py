import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_after_wait_withdrawSome_unlocks_for_caller(setup_strat, want, vault, deployer):
    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    chain.sleep(86400 * 250)  # 250 days so lock expires

    initial_b = want.balanceOf(deployer)

    ## Not enough liquid balance
    assert want.balanceOf(vault) + want.balanceOf(setup_strat) < initial_dep

    ## Yet we pull it off, because it unlocks for us
    vault.withdraw(
        initial_dep, {"from": deployer}
    )  ## Because we try to withdraw more than

    assert want.balanceOf(deployer) > initial_b  ## Want increased

    ## More accurately
    assert want.balanceOf(deployer) - initial_b >= (
        initial_dep * (10_000 - vault.withdrawalFee()) // 10_000 - 1
    )


def test_if_change_min_some_can_be_withdraw_easy(setup_strat, vault, deployer, want):

    initial_b = want.balanceOf(deployer)
    ## TODO / CHECK This is the ideal math but it seems to revert on me
    ## min = (vault.MAX_BPS() - vault.toEarnBps() - 1) * vault.balanceOf(deployer) / 10000
    min = (vault.MAX_BPS() - vault.toEarnBps() - 1) * vault.balanceOf(deployer) / 10000

    vault.withdraw(min, {"from": deployer})

    assert (
        want.balanceOf(deployer) > initial_b
    )  ## You can withdraw as long as it's less than min


def test_after_deposit_locker_has_more_funds(
    locker, deployer, vault, strategy, want, governance
):
    """
    We have to check that the Locker get's more funds after a deposit
    """
    locked, _ = locker.balances(strategy)
    intitial_in_locker = locked + locker.balanceOf(strategy)

    # Setup
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST: Did the proxy get more want?
    locked, _ = locker.balances(strategy)
    # TODO: Shouldn't this be just locker.balanceOf(strategy)?
    assert (
        locked + locker.balanceOf(strategy)
        > intitial_in_locker
    )


def test_locked_balance_after_expiration(
    locker, deployer, vault, strategy, want, governance
):
    """
    Check if locker.balance(strategy) includes both locked + unlocked amount
    """
    locked, _ = locker.balances(strategy)
    assert locked == 0
    assert locker.balanceOf(strategy) == 0

    # Setup
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance > 0
    # End Setup
    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    assert strategy.balanceOfPool() == available

    chain.sleep(10000)  # Mine so we get some interest
    chain.mine()

    # Active locked balance starts at 0
    locked1, _ = locker.balances(strategy)

    assert locked1 == available
    assert locker.balanceOf(strategy) == 0

    chain.sleep(days(7))
    chain.mine()

    # Active locked balance kicks in at the start of the next epoch
    locked2, _ = locker.balances(strategy)

    assert locked2 == available
    assert locker.balanceOf(strategy) == available

    # Locked balance becomes inactive after lock expires
    chain.sleep(days(7 * 52))
    chain.mine()

    locked3, _ = locker.balances(strategy)
    assert locked3 == available
    assert locker.balanceOf(strategy) == 0

    # Locked balance should become 0 after expired locks are processed
    strategy.manualProcessExpiredLocks({"from": deployer})

    locked3, _ = locker.balances(strategy)
    assert locked3 == 0
    assert locker.balanceOf(strategy) == 0
    assert strategy.balanceOfPool() == 0
    assert strategy.balanceOfWant() == available


def test_delegation_was_correct(deployer, vault, strategy, want, governance, randomUser, locker):
    # Setup
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    strategy.manualSetDelegate(randomUser, {"from": governance})
    assert strategy.getDelegate() == randomUser


def test_sweep_fails_no_processor(strategy, strategist):
    weth = interface.IWeth(strategy.WETH())

    with brownie.reverts():
        strategy.sweepRewards([weth], {"from": strategist})


def test_cant_sweep_want(want, strategy, strategist):
    with brownie.reverts("_onlyNotProtectedTokens"):
        strategy.sweepRewards([want], {"from": strategist})


def test_cant_take_eth(deployer, strategy):
    with brownie.reverts("onlyWhileClaiming"):
        accounts.at(deployer).transfer(strategy, "1 ether")


def test_can_set_slippage(strategy, strategist):
    strategy.setAuraBalToBalEthBptMinOutBps(10, {"from": strategist})
    assert strategy.auraBalToBalEthBptMinOutBps() == 10