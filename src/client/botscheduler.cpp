/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "botscheduler.h"
#include "game.h"
#include "creaturecache.h"
#include "localplayer.h"
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <fmt/format.h>
#include <chrono>

BotScheduler g_botScheduler;

BotScheduler::BotScheduler() {}

BotScheduler::~BotScheduler() {
    stop();
}

void BotScheduler::start() {
    if (m_running) return;
    m_running = true;
    m_paused = false;
    m_thread = std::thread(&BotScheduler::threadLoop, this);
}

void BotScheduler::clearSpells() {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_spellQueue.clear();
}

void BotScheduler::addSpell(const std::string& words, int minMana, int cooldown, int minCreatures, const std::vector<Point>& area) {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    BotSpell spell;
    spell.words = words;
    spell.minMana = minMana;
    spell.cooldown = cooldown;
    spell.minCreatures = minCreatures;
    spell.area = area;
    m_spellQueue.push_back(spell);
}

void BotScheduler::clearHeals() {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_healQueue.clear();
}

void BotScheduler::addHeal(const std::string& words, int minHealthPercent, int minMana, int cooldown) {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    BotHeal heal;
    heal.words = words;
    heal.minHealthPercent = minHealthPercent;
    heal.minMana = minMana;
    heal.cooldown = cooldown;
    m_healQueue.push_back(heal);
}

void BotScheduler::clearPotions() {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_potionQueue.clear();
}

void BotScheduler::addPotion(uint16_t itemId, int minHealthPercent, int minManaPercent, int cooldown) {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    BotPotion potion;
    potion.itemId = itemId;
    potion.minHealthPercent = minHealthPercent;
    potion.minManaPercent = minManaPercent;
    potion.cooldown = cooldown;
    m_potionQueue.push_back(potion);
}

void BotScheduler::stop() {
    m_running = false;
    if (m_thread.joinable()) {
        m_thread.join();
    }
}

void BotScheduler::setSpellQueue(const std::vector<BotSpell>& queue) {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_spellQueue = queue;
}

void BotScheduler::setHealQueue(const std::vector<BotHeal>& queue) {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_healQueue = queue;
}

void BotScheduler::updatePlayerState(uint8_t hp, uint8_t mana, const Position& pos, Otc::Direction dir) {
    m_playerHp = hp;
    m_playerMana = mana;
    m_playerX = pos.x;
    m_playerY = pos.y;
    m_playerZ = pos.z;
    m_playerDir = dir;
}

void BotScheduler::onSpellCooldown(uint16_t spellId, uint32_t delay) {
    m_lastAttackTime = g_clock.millis();
}

void BotScheduler::onSpellGroupCooldown(uint8_t groupId, uint32_t delay) {
    if (groupId == 1) { // Attack
        m_lastAttackTime = g_clock.millis();
    } else if (groupId == 2) { // Healing
        m_lastHealTime = g_clock.millis();
    }
    
    // Auto-confirm as ACK
    onCastConfirmed(delay);
}

void BotScheduler::onCastSent() {
    m_lastSentCastTime = g_clock.millis();
}

void BotScheduler::onCastConfirmed(uint32_t delay) {
    uint64_t now = g_clock.millis();
    m_lastConfirmedCastTime = now;

    uint64_t sent = m_lastSentCastTime.load();
    if (sent > 0 && now > sent) {
        double rtt = static_cast<double>(now - sent);
        
        // Rolling average: avg = (avg * 0.9) + (new * 0.1)
        double currentAvg = m_avgRtt.load();
        double newAvg = (currentAvg * 0.9) + (rtt * 0.1);
        m_avgRtt = newAvg;

        // m_dynamicSafetyMargin = clamp(avg_rtt + 5ms, 10ms, 100ms)
        int newMargin = std::max(10, std::min(100, static_cast<int>(newAvg + 5)));
        m_dynamicSafetyMargin = newMargin;
    }
}

void BotScheduler::onCastFailed() {
    // Penalize current tick on failure (exhausted) to prevent network spam
    m_lastAttackTime = g_clock.millis() + 50;
    m_lastHealTime = g_clock.millis() + 50;
}

void BotScheduler::threadLoop() {
    while (m_running) {
        if (!m_paused) {
            processCombat();
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}

void BotScheduler::processCombat() {
    uint64_t now = g_clock.millis();
    
    static int cycleCount = 0;
    static long long totalContentionUs = 0;
    
    // 1. Check HP/Mana from local atomics (updated by CreatureCache::update in Main Thread)
    int hp = m_playerHp.load();
    int mana = m_playerMana.load();

    std::lock_guard<std::mutex> lock(m_queueMutex);

    // 2. Healing Spells (Priority 1)
    for (const auto& heal : m_healQueue) {
        if (m_lastHealTime > 0 && now - m_lastHealTime < (uint64_t)heal.cooldown) continue;
        
        if (hp <= heal.minHealthPercent && mana >= heal.minMana) {
            g_dispatcher.addEvent([heal]() {
                g_game.castSpell(heal.words);
            });
            m_lastHealTime = now;
            break; 
        }
    }

    // 3. Potions (Priority 2 - Independent Cooldown)
    for (const auto& pot : m_potionQueue) {
        if (m_lastPotionTime > 0 && now - m_lastPotionTime < (uint64_t)pot.cooldown) continue;

        bool needHealth = pot.minHealthPercent > 0 && hp <= pot.minHealthPercent;
        bool needMana = pot.minManaPercent > 0 && mana <= pot.minManaPercent;

        if (needHealth || needMana) {
            g_dispatcher.addEvent([this, pot]() {
                auto player = g_game.getLocalPlayer();
                if (player) {
                    g_game.useInventoryItemWith(pot.itemId, player);
                }
            });
            m_lastPotionTime = now;
            break;
        }
    }

    // 4. Attack Spells (Priority 3 - Independent Cooldown)
    int margin = m_dynamicSafetyMargin.load();
    for (const auto& spell : m_spellQueue) {
        // Use dynamic margin for attack spells
        if (m_lastAttackTime > 0 && now - m_lastAttackTime < (uint64_t)(spell.cooldown + margin)) continue;

        if (mana >= spell.minMana) {
            // AoE Validation
            if (!spell.area.empty()) {
                // LOCK CONTENTION MEASUREMENT
                auto lockStart = std::chrono::high_resolution_clock::now();
                std::shared_lock<std::shared_mutex> cacheLock(g_creatureCache.getMutex());
                auto lockEnd = std::chrono::high_resolution_clock::now();
                
                auto contention = std::chrono::duration_cast<std::chrono::microseconds>(lockEnd - lockStart).count();
                totalContentionUs += contention;
                cycleCount++;

                if (cycleCount >= 1000) {
                    g_logger.info(fmt::format("[BotScheduler] SharedMutex contention: avg {}us | Dynamic Margin: {}ms | Avg RTT: {:.1f}ms", 
                        totalContentionUs / 1000, margin, (double)m_avgRtt.load()));
                    cycleCount = 0; totalContentionUs = 0;
                }

                Position pos(m_playerX, m_playerY, m_playerZ);
                int count = g_creatureCache.getEnemiesInArea(spell.area, pos, m_playerDir);
                if (count < spell.minCreatures) continue;
            }

            onCastSent(); // Mark potential RTT start
            g_dispatcher.addEvent([spell]() {
                g_game.castSpell(spell.words);
            });
            m_lastAttackTime = now;
            break;
        }
    }
}


