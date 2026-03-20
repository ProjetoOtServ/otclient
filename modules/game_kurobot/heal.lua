-- ==========================================
-- KuroBot Healing System
-- Adapted for new manual-tab architecture (no kurobotTabBar)
-- ==========================================

KuroBot.Heal.init = function()
  KuroBot.Heal.loadSettings()
end

KuroBot.Heal.terminate = function()
  KuroBot.Heal.saveSettings()
end

KuroBot.Heal.loadSettings = function()
  local node = g_settings.getNode('KuroBot') or {}
  if node.Heal then
    KuroBot.Heal.config = node.Heal
  end
end

KuroBot.Heal.saveSettings = function()
  local node = g_settings.getNode('KuroBot') or {}
  node.Heal = KuroBot.Heal.config
  g_settings.setNode('KuroBot', node)
  g_settings.save()
end
