import pytest
import json

from brownie import TheVault, MyStrategy, accounts, Contract, web3, interface

SETT_ADDRESS = "0xBA485b556399123261a5F9c95d413B4f93107407"
STRAT_ADDRESS = "0x3c0989eF27e3e3fAb87a2d7C38B35880C90E63b5"

NEW_REWARDS_DISTRIBUTOR = "0xa9b08B4CeEC1EF29EdEC7F9C94583270337D6416"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"


@pytest.fixture
def vault_proxy():
    return TheVault.at(SETT_ADDRESS)


@pytest.fixture
def strat_proxy():
    return MyStrategy.at(STRAT_ADDRESS)


@pytest.fixture
def proxy_admin():
    ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
    admin = web3.eth.getStorageAt(STRAT_ADDRESS, ADMIN_SLOT).hex()
    return Contract.from_explorer(admin)


@pytest.fixture
def proxy_admin_gov(proxy_admin):
    """
    Also found at proxy_admin.owner()
    """
    return accounts.at(proxy_admin.owner(), force=True)


@pytest.fixture
def strategist(strat_proxy):
    return accounts.at(strat_proxy.strategist(), force=True)


@pytest.fixture
def usdc():
    usdc = interface.IERC20Detailed(USDC)
    return usdc


@pytest.mark.skip(reason="May depend on mainnet conditions, run when evaluating upgrades")
def test_check_storage_integrity(
    strat_proxy, vault_proxy, deployer, proxy_admin, proxy_admin_gov, usdc, strategist
):
    old_want = strat_proxy.want()
    old_vault = strat_proxy.vault()
    old_withdrawalMaxDeviationThreshold = strat_proxy.withdrawalMaxDeviationThreshold()
    old_autoCompoundRatio = strat_proxy.autoCompoundRatio()
    old_withdrawalSafetyCheck = strat_proxy.withdrawalSafetyCheck()
    old_processLocksOnReinvest = strat_proxy.processLocksOnReinvest()
    old_bribesProcessor = strat_proxy.bribesProcessor()
    old_auraBalToBalEthBptMinOutBps = strat_proxy.auraBalToBalEthBptMinOutBps()

    logic = MyStrategy.deploy({"from": deployer})

    ## Do the Upgrade
    proxy_admin.upgrade(strat_proxy, logic, {"from": proxy_admin_gov})

    ## Check Integrity
    assert old_want == strat_proxy.want()
    assert old_vault == strat_proxy.vault()
    assert (
        old_withdrawalMaxDeviationThreshold
        == strat_proxy.withdrawalMaxDeviationThreshold()
    )
    assert old_autoCompoundRatio == strat_proxy.autoCompoundRatio()
    assert old_withdrawalSafetyCheck == strat_proxy.withdrawalSafetyCheck()
    assert old_processLocksOnReinvest == strat_proxy.processLocksOnReinvest()
    assert old_bribesProcessor == strat_proxy.bribesProcessor()
    assert old_auraBalToBalEthBptMinOutBps == strat_proxy.auraBalToBalEthBptMinOutBps()

    ## === Test claiming the current round of bribes === ##
    intial_balance = usdc.balanceOf(strat_proxy.bribesProcessor())

    with open("tests/upgrade/data/hh_claim_data_7_23.json", "r") as read_file:
        data = json.load(read_file)["data"]

    ## Block taken from badger-multisig script
    ## Reference: https://github.com/Badger-Finance/badger-multisig/blob/0a98cb268661b63221195eb4683cfadfa05e0120/great_ape_safe/ape_api/badger.py#L164
    def transform_claimable(amount_string, n_decimals):
        # if the last number is a zero it gets omitted by the api,
        # here we pad the matissa with zeroes to correct for this
        assert "." in amount_string
        splitted = amount_string.split(".")
        return splitted[0] + splitted[-1].ljust(n_decimals, "0")

    aggregate = {"tokens": [], "amounts": []}
    for item in data:
        aggregate["tokens"].append(item["token"])
        aggregate["amounts"].append(
            transform_claimable(item["claimable"], item["decimals"])
        )

    metadata = [
        (
            item["claimMetadata"]["identifier"],
            item["claimMetadata"]["account"],
            item["claimMetadata"]["amount"],
            item["claimMetadata"]["merkleProof"],
        )
        for item in data
    ]

    strat_proxy.claimBribesFromHiddenHand(
        NEW_REWARDS_DISTRIBUTOR, metadata, {"from": strategist}
    )
    # Confirm that claimable amount was claimed and transferred to the Bribes Processor
    amount = aggregate["amounts"][aggregate["tokens"].index(USDC)]
    assert usdc.balanceOf(strat_proxy.bribesProcessor()) - intial_balance == amount
    print(f"USDC Claimed: {amount}")
