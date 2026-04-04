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

#pragma once

#include "declarations.h"
#include <framework/core/declarations.h>
#include <framework/util/point.h>
#include <thread>
#include <atomic>
#include <mutex>
#include <vector>
#include <string>

struct BotSpell {
    std::string words;
    int minMana;
    int minManaPercent;
    int cooldown;
    std::vector<Point> area;
    int minCreatures;
};

struct BotHeal {
    std::string words;
    int minHealthPercent;
    int minMana;
    int cooldown;
};

struct BotPotion {
    uint16_t itemId;
    int minHealthPercent;
    int minManaPercent;
    int cooldown;
    bool useWith;
};

//@bindsingleton g_botScheduler
class BotScheduler {
public:
    BotScheduler();
    ~BotScheduler();

    void start();
    void stop();
    void pause() { m_paused = true; }
    void resume() { m_paused = false; }
    bool isRunning() const { return m_running; }

    void clearSpells();
    void addSpell(const std::string& words, int minMana, int cooldown, int minCreatures, const std::vector<Point>& area);
    
    void clearHeals();
    void addHeal(const std::string& words, int minHealthPercent, int minMana, int cooldown);

    void clearPotions();
    void addPotion(uint16_t itemId, int minHealthPercent, int minManaPercent, int cooldown);

    void setSpellQueue(const std::vector<BotSpell>& queue);
    void setHealQueue(const std::vector<BotHeal>& queue);

    // Dynamic state updates from Main Thread
    void updatePlayerState(uint8_t hp, uint8_t mana, const Position& pos, Otc::Direction dir);
    void onSpellCooldown(uint16_t spellId, uint32_t delay);
    void onSpellGroupCooldown(uint8_t groupId, uint32_t delay);

    // ACK Interceptor Hooks
    void onCastSent();
    void onCastConfirmed(uint32_t delay);
    void onCastFailed();

private:
    void threadLoop();
    void processCombat();

    std::thread m_thread;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_paused{false};

    std::vector<BotSpell> m_spellQueue;
    std::vector<BotHeal> m_healQueue;
    std::vector<BotPotion> m_potionQueue;
    std::mutex m_queueMutex;

    // Player Status (Atomic)
    std::atomic<int> m_playerHp{0};
    std::atomic<int> m_playerMana{0};
    std::atomic<int> m_playerX{0}, m_playerY{0};
    std::atomic<int> m_playerZ{0};
    std::atomic<Otc::Direction> m_playerDir{Otc::South};
    std::atomic<int> m_consecutiveFailures{0};

    // Cooldown trackers (ticks)
    std::atomic<uint64_t> m_lastAttackTime{0};
    std::atomic<uint64_t> m_lastHealTime{0};
    std::atomic<uint64_t> m_lastPotionTime{0};

    // RTT & Dynamic Safety
    std::atomic<uint64_t> m_lastSentCastTime{0};
    std::atomic<uint64_t> m_lastConfirmedCastTime{0};
    std::atomic<double>   m_avgRtt{20.0};
    std::atomic<int>      m_dynamicSafetyMargin{30};
};


extern BotScheduler g_botScheduler;
