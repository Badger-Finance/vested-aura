from brownie import * 

import pytest

SETT_ADDRESS = "0xBA485b556399123261a5F9c95d413B4f93107407"
STRAT_ADDRESS = "0x3c0989eF27e3e3fAb87a2d7C38B35880C90E63b5"

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

def test_check_storage_integrity(strat_proxy, vault_proxy, deployer, proxy_admin, proxy_admin_gov):
  old_want = strat_proxy.want()
  old_vault = strat_proxy.vault()
  old_withdrawalMaxDeviationThreshold = strat_proxy.withdrawalMaxDeviationThreshold()
  old_autoCompoundRatio = strat_proxy.autoCompoundRatio()

  old_withdrawalSafetyCheck = strat_proxy.withdrawalSafetyCheck()
   
  old_processLocksOnReinvest = strat_proxy.processLocksOnReinvest()

  old_bribesProcessor = strat_proxy.bribesProcessor()

  ## Do the Upgrade
  new_strat_logic = MyStrategy.deploy({"from": deployer})
  proxy_admin.upgrade(strat_proxy, new_strat_logic, {"from": proxy_admin_gov})

  ## Check Integrity
  assert old_want == strat_proxy.want()
  assert old_vault == strat_proxy.vault()
  assert old_withdrawalMaxDeviationThreshold == strat_proxy.withdrawalMaxDeviationThreshold()
  assert old_autoCompoundRatio == strat_proxy.autoCompoundRatio()

  assert old_withdrawalSafetyCheck == strat_proxy.withdrawalSafetyCheck()
   
  assert old_processLocksOnReinvest == strat_proxy.processLocksOnReinvest()

  assert old_bribesProcessor == strat_proxy.bribesProcessor()

  ## Let's do a quick earn and harvest as well
  vault_proxy.earn({"from": accounts.at(vault_proxy.governance(), force=True)})

  strat_proxy.harvest({"from": accounts.at(vault_proxy.governance(), force=True)})