import pytest

from brownie import (
    accounts,
    interface,
    web3,
    MockBribesProcessor,
    MockRewardDistributor,
)

ETH_IDENTIFIER = web3.keccak(text="ETH")
WANT_IDENTIFIER = web3.keccak(text="WANT")

@pytest.fixture
def bribes_processor(deployer, strategy, governance):
    processor = MockBribesProcessor.deploy({"from": deployer})
    strategy.setBribesProcessor(processor, {"from": governance})
    return processor


@pytest.fixture
def reward_distributor(want, deployer):
    distributor = MockRewardDistributor.deploy({"from": deployer})

    accounts.at(deployer).transfer(distributor, "1 ether")

    distributor.addReward(WANT_IDENTIFIER, want, {"from": deployer})
    amount = want.balanceOf(deployer) // 2
    want.transfer(distributor, amount, {"from": deployer})
    return distributor


def test_claim_bribes(want, strategy, bribes_processor, reward_distributor, strategist, deployer):
    balance_before = want.balanceOf(bribes_processor)

    amount = want.balanceOf(deployer) // 2
    assert amount > 0

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [(WANT_IDENTIFIER, strategy, amount, [])],
        {"from": strategist}
    )

    assert want.balanceOf(bribes_processor) == balance_before + amount

    assert claim_tx.events["RewardsCollected"]["token"] == want
    assert claim_tx.events["RewardsCollected"]["amount"] == amount


def test_claim_eth_bribes(strategy, strategist, bribes_processor, reward_distributor):
    balance_before = accounts.at(bribes_processor, force=True).balance()

    amount = 1e18

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [(ETH_IDENTIFIER, strategy, amount, [])],
        {"from": strategist}
    )

    weth = interface.IERC20Detailed(strategy.WETH())
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
