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
#include "map.h"
#include "creature.h"
#include "creaturecache.h"
#include "localplayer.h"
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <fmt/format.h>
#include <algorithm>
#include <chrono>

BotScheduler g_botScheduler;

BotScheduler::BotScheduler() {
    uint64_t now = g_clock.millis();
    m_lastAttackTime = now;
    m_lastHealTime = now;
}

BotScheduler::~BotScheduler() {
    stop();
}

void BotScheduler::start() {
    if (m_running) return;
    m_running = true;
    m_paused = false;
    // Sincroniza timers com o tempo atual para evitar burst inicial
    uint64_t now = g_clock.millis();
    m_lastHealTime = now;
    m_lastAttackTime = now;
    m_consecutiveFailures = 0;
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
    // Para a thread de Auto Target sem depender de m_running
    stopAutoTarget();
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
    uint64_t now = g_clock.millis();
    m_lastConfirmedCastTime = now;
    m_consecutiveFailures = 0; // Success!

    if (groupId == 1) { // Attack
        m_lastAttackTime = now + delay - m_dynamicSafetyMargin.load();
    } else if (groupId == 2) { // Healing
        m_lastHealTime = now + delay;
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
    m_consecutiveFailures = 0; // Any success resets penalty

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
    uint64_t now = g_clock.millis();
    int failures = ++m_consecutiveFailures;
    
    // Scaling penalty: 1s, 2s, or 3s based on failures
    int penalty = std::min(3000, failures * 1000);
    
    m_lastAttackTime = now + penalty;
    m_lastHealTime = now + penalty;
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
    
    static int callCount = 0;
    if (++callCount % 1000 == 0) {
        g_logger.info(fmt::format("[BotScheduler] processCombat chamado {} vezes, lastHeal={}, now={}",
            callCount, m_lastHealTime.load(), g_clock.millis()));
    }
    
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

// =============================================================
// AUTO TARGET ENGINE — ISOLADO
// Nao depende de m_running. Roda sua propria thread.
// Todo o acesso ao mapa ocorre dentro do g_dispatcher (Main Thread).
// =============================================================

void BotScheduler::stopAutoTarget() {
    m_autoTargetEnabled = false;
    if (m_autoTargetThread.joinable()) {
        m_autoTargetThread.join();
    }
}

void BotScheduler::setAutoTarget(bool enabled, const std::string& mode) {
    m_autoTargetEnabled = enabled;
    if (!mode.empty())
        m_targetMode = mode[0];

    if (enabled) {
        // Inicia thread dedicada apenas se ainda nao estiver rodando
        if (!m_autoTargetThread.joinable()) {
            m_autoTargetThread = std::thread(&BotScheduler::autoTargetLoop, this);
        }
    } else {
        // Sinaliza cancelamento do ataque atual na Main Thread
        m_currentTargetId = 0;
        g_dispatcher.addEvent([]() {
            if (g_game.isOnline())
                g_game.cancelAttack();
        });
        // Thread vai se encerrar sozinha ao ver m_autoTargetEnabled == false
        if (m_autoTargetThread.joinable()) {
            m_autoTargetThread.join();
        }
    }
}

void BotScheduler::autoTargetLoop() {
    while (m_autoTargetEnabled.load()) {
        processAutoTarget();
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}

void BotScheduler::processAutoTarget() {
    if (!m_autoTargetEnabled)
        return;

    // ── GATEKEEPER: verifica cooldown ANTES de enfileirar no dispatcher ──────
    // Isso evita que a Main Thread receba 20 eventos/s que seriam descartados
    // depois. O static e thread-local porque esta funcao roda em uma unica
    // thread (autoTargetLoop), entao nao ha risco de corrida.
    static uint64_t lastDispatch = 0;
    uint64_t nowBg = g_clock.millis();
    if (nowBg - lastDispatch < 1000) return;
    lastDispatch = nowBg;

    // Captura atomics antes de entrar no dispatcher
    char     mode  = m_targetMode.load();
    char     lastMode = m_lastTargetMode.load();
    uint32_t curId = m_currentTargetId.load();

    // TODA a interacao com o mapa/criaturas ocorre na Main Thread via dispatcher
    g_dispatcher.addEvent([this, mode, curId, lastMode]() {
        // ── KILL SWITCH: descarta eventos enfileirados apos desativacao ─────
        if (!m_autoTargetEnabled) return;

        if (!g_game.isOnline()) return;

        auto player = g_game.getLocalPlayer();
        if (!player) return;

        auto playerPos = player->getPosition();
        int  pz        = playerPos.z;
        uint32_t pid   = player->getId();

        bool modeChanged = (mode != lastMode);

        // ── STICKINESS ABSOLUTA: se ja esta atacando algo valido, nao faz nada
        // O bot so busca novo alvo quando o jogador estiver ocioso (sem alvo).
        auto attacking = g_game.getAttackingCreature();
        if (!modeChanged && attacking
            && !attacking->isDead()
            && attacking->getHealthPercent() > 0
            && !attacking->isRemoved()
            && attacking->getPosition().z == pz) {
            // Garante que m_currentTargetId reflete o alvo atual do cliente
            m_currentTargetId = attacking->getId();
            return; // Alvo valido → sem troca, sem pacote extra
        }
        
        m_lastTargetMode = mode;

        // Se chegou aqui: modo mudou, jogador esta ocioso ou alvo morreu/saiu → buscar novo alvo

        // Varredura segura: g_map.getSpectators apenas na Main Thread
        auto spectators = g_map.getSpectators(playerPos, false);

        // Distancia de Chebyshev
        auto chebyshev = [&](const CreaturePtr& c) -> int {
            auto p = c->getPosition();
            return std::max(std::abs(p.x - playerPos.x), std::abs(p.y - playerPos.y));
        };

        // Filtro estrito: aceita apenas monstros vivos no mesmo andar.
        std::vector<CreaturePtr> candidates;
        candidates.reserve(spectators.size());
        for (const auto& c : spectators) {
            if (!c)                              continue; // nulo
            if (c->isRemoved())                  continue; // saiu do mapa
            if (c->isDead() || c->getHealthPercent() <= 0) continue; // hp=0 (Limpeza de Fantasmas)
            if (c->getId() == pid)               continue; // o proprio player
            if (c->isPlayer())                   continue; // outros jogadores
            if (c->getPosition().z != pz)        continue; // andar diferente
            if (!c->isMonster())                 continue; // NPC / outra coisa
            candidates.push_back(c);
        }

        if (candidates.empty()) {
            m_currentTargetId = 0;
            return;
        }

        // Score de cluster para Modo E
        auto clusterScore = [&](const CreaturePtr& c) -> int {
            int count = 0;
            auto cp = c->getPosition();
            for (const auto& other : candidates) {
                if (other->getId() == c->getId()) continue;
                auto op = other->getPosition();
                if (std::abs(op.x - cp.x) <= 2 && std::abs(op.y - cp.y) <= 2)
                    ++count;
            }
            return count;
        };

        // Ordena pelo modo selecionado (A-I)
        std::sort(candidates.begin(), candidates.end(),
            [&](const CreaturePtr& a, const CreaturePtr& b) -> bool {
                int da = chebyshev(a), db = chebyshev(b);
                int ha = a->getHealthPercent(), hb = b->getHealthPercent();
                switch (mode) {
                    case 'A': return da < db;
                    case 'B': return da > db;
                    case 'C': return ha < hb;
                    case 'D': return ha > hb;
                    case 'E': return clusterScore(a) > clusterScore(b);
                    case 'F': return da != db ? (da < db) : (ha < hb);
                    case 'G': return da != db ? (da < db) : (ha > hb);
                    case 'H': return da != db ? (da > db) : (ha < hb);
                    case 'I': return da != db ? (da > db) : (ha > hb);
                    default:  return da < db;
                }
            }
        );

        auto best = candidates.front();
        m_currentTargetId = best->getId();
        g_game.attack(best);
    });
}

