import pytest
import brownie

from brownie import (
    accounts,
    interface,
    web3,
    MockBribesProcessor,
)

BADGER = "0x3472A5A71965499acd81997a54BBA8D852C6E53d"
BADGER_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC"

ETH_IDENTIFIER = web3.keccak(text="ETH")
BADGER_IDENTIFIER = web3.keccak(text="BADGER")
WANT_IDENTIFIER = web3.keccak(text="WANT")


@pytest.fixture
def badger(deployer):
    badger = interface.IERC20Detailed(BADGER)
    badger.transfer(deployer, 100e18, {"from": BADGER_WHALE})
    return badger


@pytest.fixture
def bribes_processor(deployer, strategy, governance):
    processor = MockBribesProcessor.deploy({"from": deployer})
    strategy.setBribesProcessor(processor, {"from": governance})
    return processor


@pytest.fixture(autouse=True)
def reward_distributor_setup(want, badger, deployer, reward_distributor):
    accounts.at(deployer).transfer(reward_distributor, "1 ether")

    reward_distributor.addReward(WANT_IDENTIFIER, want, {"from": deployer})
    amount = want.balanceOf(deployer) // 2
    want.transfer(reward_distributor, amount, {"from": deployer})

    reward_distributor.addReward(BADGER_IDENTIFIER, badger, {"from": deployer})
    amount = badger.balanceOf(deployer) // 2
    badger.transfer(reward_distributor, amount, {"from": deployer})
    return reward_distributor


def test_claim_bribes(want, strategy, bribes_processor, reward_distributor, strategist, deployer):
    balance_before = want.balanceOf(bribes_processor)

    amount = want.balanceOf(deployer) // 2
    assert amount > 0

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [
            (WANT_IDENTIFIER, strategy, amount, []), 
        ],
        {"from": strategist}
    )

    assert want.balanceOf(bribes_processor) == balance_before + amount

    assert claim_tx.events["RewardsCollected"]["token"] == want
    assert claim_tx.events["RewardsCollected"]["amount"] == amount


def test_claim_bribes_badger(badger, badgerTree, strategy, reward_distributor, bribes_processor, strategist, deployer):
    balance_before = badger.balanceOf(badgerTree)

    amount = badger.balanceOf(deployer) // 2
    assert amount > 0

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [
            (BADGER_IDENTIFIER, strategy, amount, [])
        ],
        {"from": strategist}
    )

    assert badger.balanceOf(badgerTree) == balance_before + amount

    assert claim_tx.events["TreeDistribution"]["token"] == badger
    assert claim_tx.events["TreeDistribution"]["amount"] == amount


def test_claim_eth_bribes(strategy, strategist, bribes_processor, reward_distributor):
    weth = interface.IERC20Detailed(strategy.WETH())
    balance_before = weth.balanceOf(bribes_processor)

    amount = 1e18

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [(ETH_IDENTIFIER, strategy, amount, [])],
        {"from": strategist}
    )

    assert weth.balanceOf(bribes_processor) == balance_before + amount

    assert claim_tx.events["RewardsCollected"]["token"] == weth
    assert claim_tx.events["RewardsCollected"]["amount"] == amount


def test_sweep_weth(strategy, strategist, bribes_processor, deployer):
    amount = 1e18

    weth = interface.IWeth(strategy.WETH())
    weth.deposit({"from": deployer, "value": amount})

    weth = interface.IERC20Detailed(weth.address)
    weth.transfer(strategy, amount, {"from": deployer})

    balance_before_proc = weth.balanceOf(bribes_processor)

    # Sweep
    strategy.sweepRewards([weth], {"from": strategist})

    assert weth.balanceOf(strategy) == 0
    assert weth.balanceOf(bribes_processor) == balance_before_proc + amount


def test_bribe_claiming_no_processor(want, deployer, strategy, strategist, reward_distributor):
    with brownie.reverts("Bribes processor not set"):
        amount = want.balanceOf(deployer) // 2
        strategy.claimBribesFromHiddenHand(
            reward_distributor,
            [
                (WANT_IDENTIFIER, strategy, amount, []), 
            ],
            {"from": strategist}
        )
