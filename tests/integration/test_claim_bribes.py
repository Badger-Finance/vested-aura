import pytest
import brownie
from helpers.constants import AddressZero
from brownie import accounts, interface, web3

# Tokens
BADGER = "0x3472A5A71965499acd81997a54BBA8D852C6E53d"
GNO = "0x6810e776880C02933D47DB1b9fc05908e5386b96"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

# Whales
BADGER_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC"
GNO_WHALE = "0xeC83f750adfe0e52A8b0DbA6eeB6be5Ba0beE535"
USDC_WHALE = "0x0A59649758aa4d66E25f08Dd01271e891fe52199"

WETH_IDENTIFIER = web3.keccak(text="WETH")
BADGER_IDENTIFIER = web3.keccak(text="BADGER")
WANT_IDENTIFIER = web3.keccak(text="WANT")
GNO_IDENTIFIER = web3.keccak(text="GNO")
USDC_IDENTIFIER = web3.keccak(text="USDC")


@pytest.fixture
def badger(deployer):
    badger = interface.IERC20Detailed(BADGER)
    badger.transfer(deployer, 100e18, {"from": BADGER_WHALE})
    return badger


@pytest.fixture
def gno(deployer):
    gno = interface.IERC20Detailed(GNO)
    gno.transfer(deployer, 100e18, {"from": GNO_WHALE})
    return gno


@pytest.fixture
def usdc(deployer):
    usdc = interface.IERC20Detailed(USDC)
    usdc.transfer(deployer, 100e8, {"from": USDC_WHALE})
    return usdc


@pytest.fixture
def weth(deployer, strategy):
    amount = 2e18
    weth = interface.IWeth(strategy.WETH())
    weth.deposit({"from": deployer, "value": amount})
    weth = interface.IERC20Detailed(weth.address)
    return weth


@pytest.fixture(autouse=True)
def reward_distributor_setup(
    want, badger, gno, usdc, weth, deployer, reward_distributor
):
    accounts.at(deployer).transfer(reward_distributor, "1 ether")

    reward_distributor.addReward(WANT_IDENTIFIER, want, {"from": deployer})
    amount = want.balanceOf(deployer) // 2
    want.transfer(reward_distributor, amount, {"from": deployer})

    reward_distributor.addReward(BADGER_IDENTIFIER, badger, {"from": deployer})
    amount = badger.balanceOf(deployer) // 2
    badger.transfer(reward_distributor, amount, {"from": deployer})

    reward_distributor.addReward(GNO_IDENTIFIER, gno, {"from": deployer})
    amount = gno.balanceOf(deployer) // 2
    gno.transfer(reward_distributor, amount, {"from": deployer})

    reward_distributor.addReward(USDC_IDENTIFIER, usdc, {"from": deployer})
    amount = usdc.balanceOf(deployer) // 2
    usdc.transfer(reward_distributor, amount, {"from": deployer})

    reward_distributor.addReward(WETH_IDENTIFIER, weth, {"from": deployer})
    amount = weth.balanceOf(deployer) // 2
    weth.transfer(reward_distributor, amount, {"from": deployer})

    return reward_distributor


@pytest.fixture
def gno_recepient():
    return accounts[7]


@pytest.fixture
def weth_recepient():
    return accounts[9]


def test_claim_bribes(
    want, strategy, bribes_processor, reward_distributor, strategist, deployer
):
    balance_before = want.balanceOf(bribes_processor)

    amount = want.balanceOf(deployer) // 2
    assert amount > 0

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [
            (WANT_IDENTIFIER, strategy, amount, []),
        ],
        {"from": strategist},
    )

    assert want.balanceOf(bribes_processor) == balance_before + amount

    assert claim_tx.events["RewardsCollected"]["token"] == want
    assert claim_tx.events["RewardsCollected"]["amount"] == amount


def test_claim_eth_bribes(strategy, strategist, bribes_processor, reward_distributor):
    weth = interface.IERC20Detailed(strategy.WETH())
    balance_before = weth.balanceOf(bribes_processor)

    amount = 1e18

    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [(WETH_IDENTIFIER, strategy, amount, [])],
        {"from": strategist},
    )

    assert weth.balanceOf(bribes_processor) == balance_before + amount

    assert claim_tx.events["RewardsCollected"]["token"] == weth
    assert claim_tx.events["RewardsCollected"]["amount"] == amount


def test_sweep_weth(strategy, strategist, bribes_processor, deployer, weth):
    amount = 1e18
    weth.transfer(strategy, amount, {"from": deployer})

    balance_before_proc = weth.balanceOf(bribes_processor)

    # Sweep
    strategy.sweepRewards([weth], {"from": strategist})

    assert weth.balanceOf(strategy) == 0
    assert weth.balanceOf(bribes_processor) == balance_before_proc + amount


def test_bribe_claiming_no_processor(
    want, deployer, strategy, strategist, reward_distributor
):
    with brownie.reverts("Bribes processor not set"):
        amount = want.balanceOf(deployer) // 2
        strategy.claimBribesFromHiddenHand(
            reward_distributor,
            [
                (WANT_IDENTIFIER, strategy, amount, []),
            ],
            {"from": strategist},
        )


def test_claim_bribes_with_redirection(
    badger,
    gno,
    usdc,
    weth,
    gno_recepient,
    weth_recepient,
    vault,
    strategy,
    reward_distributor,
    bribes_processor,
    strategist,
    deployer,
    governance,
):
    treasury = vault.treasury()

    # Setting BADGER to be redirected to deployer with a fee
    strategy.setRedirectionToken(badger, deployer, 1500, {"from": governance})
    assert strategy.bribesRedirectionPaths(badger) == deployer
    assert strategy.redirectionFees(badger) == 1500

    # Calling again for BADGER changes settings to treausury as recepeint and 0 fee
    strategy.setRedirectionToken(badger, treasury, 0, {"from": governance})
    assert strategy.bribesRedirectionPaths(badger) == treasury
    assert strategy.redirectionFees(badger) == 0

    # Test invalid settings
    with brownie.reverts("Invalid token address"):
        strategy.setRedirectionToken(AddressZero, treasury, 0, {"from": governance})
    with brownie.reverts("Invalid recepient address"):
        strategy.setRedirectionToken(badger, AddressZero, 0, {"from": governance})
    with brownie.reverts("Invalid redirection fee"):
        strategy.setRedirectionToken(badger, treasury, 20000, {"from": governance})

    # Setting GNO to be redirected to its intended recepient with a 15% fee
    strategy.setRedirectionToken(gno, gno_recepient, 1500, {"from": governance})
    assert strategy.bribesRedirectionPaths(gno) == gno_recepient
    assert strategy.redirectionFees(gno) == 1500

    # Setting ETH to be redirected to its intended recepient with a 10% fee
    strategy.setRedirectionToken(weth, weth_recepient, 1000, {"from": governance})
    assert strategy.bribesRedirectionPaths(weth) == weth_recepient
    assert strategy.redirectionFees(weth) == 1000

    # NOTE: USDC is not redirected

    badger_amount = badger.balanceOf(reward_distributor)
    gno_amount = gno.balanceOf(reward_distributor)
    usdc_amount = usdc.balanceOf(reward_distributor)
    eth_amount = reward_distributor.balance()
    assert badger_amount > 0
    assert gno_amount > 0
    assert usdc_amount > 0
    assert eth_amount > 0

    badger_recepient_balance_before = badger.balanceOf(treasury)
    gno_recepient_balance_before = gno.balanceOf(gno_recepient)
    weth_recepient_balance_before = weth.balanceOf(weth_recepient)
    usdc_processor_balance_before = usdc.balanceOf(bribes_processor)

    # Batch claim tokens
    claim_tx = strategy.claimBribesFromHiddenHand(
        reward_distributor,
        [
            (BADGER_IDENTIFIER, strategy, badger_amount, []),
            (GNO_IDENTIFIER, strategy, gno_amount, []),
            (USDC_IDENTIFIER, strategy, usdc_amount, []),
            (WETH_IDENTIFIER, strategy, eth_amount, []),
        ],
        {"from": strategist},
    )

    # Check that redirection fee was processed
    event = claim_tx.events["RedirectionFee"]
    assert len(event) == 2  # Both GNO and ETH have fees assigned to them
    # Confirm GNO event
    expected_gno_fee_amount = gno_amount * strategy.redirectionFees(gno) / 10000
    assert event[0]["destination"] == treasury
    assert event[0]["token"] == gno
    assert event[0]["amount"] == expected_gno_fee_amount
    assert gno.balanceOf(treasury) == expected_gno_fee_amount
    # Confirm ETH event
    expected_weth_fee_amount = eth_amount * strategy.redirectionFees(weth) / 10000
    assert event[1]["destination"] == treasury
    assert event[1]["token"] == weth
    assert event[1]["amount"] == expected_weth_fee_amount
    assert weth.balanceOf(treasury) == expected_weth_fee_amount

    # Check that the TokenRedirection event was emitted
    event = claim_tx.events["TokenRedirection"]
    assert len(event) == 3
    # Confirm BADGER event
    assert event[0]["destination"] == treasury
    assert event[0]["token"] == badger
    assert event[0]["amount"] == badger_amount
    # Confirm GNO event
    assert event[1]["destination"] == gno_recepient
    assert event[1]["token"] == gno
    assert (
        event[1]["amount"]
        == gno_recepient_balance_before + gno_amount - expected_gno_fee_amount
    )
    # Confirm ETH event
    assert event[2]["destination"] == weth_recepient
    assert event[2]["token"] == weth
    assert (
        event[2]["amount"]
        == weth_recepient_balance_before + eth_amount - expected_weth_fee_amount
    )

    # Check accounting
    assert badger.balanceOf(treasury) == badger_recepient_balance_before + badger_amount
    assert (
        gno.balanceOf(gno_recepient)
        == gno_recepient_balance_before + gno_amount - expected_gno_fee_amount
    )
    assert (
        weth.balanceOf(weth_recepient)
        == weth_recepient_balance_before + eth_amount - expected_weth_fee_amount
    )
    assert (
        usdc.balanceOf(bribes_processor) == usdc_processor_balance_before + usdc_amount
    )
