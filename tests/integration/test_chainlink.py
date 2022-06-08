import pytest
import brownie
from brownie import *
from helpers.constants import EmptyBytes32
from eth_utils import encode_hex

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""

def test_chainlink_checkUpkeep_works_when_a_lock_is_expired(setup_strat, want, vault, deployer, randomUser, locker):
    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    ## Random operation for ganache to wake up
    want.approve(locker, 123, {"from": deployer})

    ## Nothing to unlock
    # check = setup_strat.checkUpkeep(EmptyBytes32)
    # assert check[0] == False
    ## NOTE: Commented because ganache breaks here and says there's stuff to unlock although lock is not expired
    ## Trying to claim breaks as lock is not expired even though in view math it works


    chain.sleep(86400 * 250)  # 250 days so lock expires

    ## Random operation for ganache to wake up
    want.approve(locker, 123, {"from": deployer})

    ## Lock has expired, should return true
    check = setup_strat.checkUpkeep(EmptyBytes32)
    assert check[0] == True

    ## Process the lock here
    setup_strat.performUpkeep(EmptyBytes32, {"from": randomUser})


def test_manual_process_any_can_call(setup_strat, want, vault, deployer, randomUser, locker):
    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    chain.sleep(86400 * 250)  # 250 days so lock expires


    ## A random function to avoid Ganache Simulation isues
    want.approve(locker, 123, {"from": deployer})

    ## Process the lock here
    initial_strat_b = want.balanceOf(setup_strat)

    in_locker_balance, _ = locker.balances(setup_strat)

    unlocked_bal = in_locker_balance - locker.balanceOf(setup_strat)

    assert unlocked_bal > 0

    setup_strat.manualProcessExpiredLocks({"from": randomUser})

    ## Unlock successful
    assert want.balanceOf(setup_strat) > initial_strat_b

    ## More rigorously, we got the exact unlocked_bal
    assert want.balanceOf(setup_strat) == initial_strat_b + unlocked_bal

def test_chainlink_function_unlocks(setup_strat, want, vault, deployer, randomUser, locker):
    """
      Same test as above but done via the performUpkeep function
    """
    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    chain.sleep(86400 * 250)  # 250 days so lock expires

    ## A random function to avoid Ganache Simulation isues
    want.approve(locker, 123, {"from": deployer})

    ## Process the lock here
    initial_strat_b = want.balanceOf(setup_strat)
    
    in_locker_balance, _ = locker.balances(setup_strat)

    unlocked_bal = in_locker_balance - locker.balanceOf(setup_strat)

    setup_strat.performUpkeep(EmptyBytes32, {"from": randomUser})

    ## Unlock successful
    assert want.balanceOf(setup_strat) > initial_strat_b

    ## More rigorously, we got the exact unlocked_bal
    assert want.balanceOf(setup_strat) == initial_strat_b + unlocked_bal