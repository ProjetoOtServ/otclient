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

#include "creaturecache.h"
#include "map.h"
#include "game.h"
#include "localplayer.h"
#include "protocolcodes.h"
#include <fmt/format.h>
#include "botscheduler.h"
#include <utility>
#include <chrono>

CreatureCache g_creatureCache;

void CreatureCache::update()
{
    auto localPlayer = g_game.getLocalPlayer();
    if (localPlayer) {
        g_botScheduler.updatePlayerState(
            localPlayer->getHealthPercent(),
            localPlayer->getManaPercent(),
            localPlayer->getPosition(),
            g_game.getServerDirection()
        );
    }

    std::unique_lock<std::shared_mutex> lock(m_mutex);
    m_creatures.clear();

    const auto& creatures = g_map.getCreatures();
    m_creatures.reserve(creatures.size());

    for (const auto& it : creatures) {
        const auto& creature = it.second;
        if (!creature || creature->isRemoved())
            continue;

        CachedCreature cc;
        cc.id = creature->getId();
        cc.name = creature->getName();
        cc.pos = creature->getPosition();
        cc.healthPercent = creature->getHealthPercent();
        cc.type = creature->getType();

        m_creatures.emplace_back(std::move(cc));
    }
}

std::vector<CachedCreature> CreatureCache::getCreatures()
{
    std::shared_lock<std::shared_mutex> lock(m_mutex);
    return m_creatures;
}

int CreatureCache::getEnemiesInArea(const std::vector<Point>& areaOffsets, const Position& centerPos, Otc::Direction direction)
{
    auto start = std::chrono::high_resolution_clock::now();
    std::shared_lock<std::shared_mutex> lock(m_mutex);
    int count = 0;

    // Pre-calculate transformed offsets
    std::vector<Point> transformedOffsets;
    transformedOffsets.reserve(areaOffsets.size());

    for (const auto& pt : areaOffsets) {
        Point t;
        switch (direction) {
            case Otc::North: t = pt; break;
            case Otc::East:  t = Point(-pt.y, pt.x); break;
            case Otc::South: t = Point(-pt.x, -pt.y); break;
            case Otc::West:  t = Point(pt.y, -pt.x); break;
            default: t = pt; break;
        }
        transformedOffsets.emplace_back(t);
    }

    const auto localPlayerId = g_game.isOnline() ? g_game.getLocalPlayer()->getId() : 0;

    for (const auto& cc : m_creatures) {
        // Only count monsters and players (excluding local player)
        if (cc.type != Proto::CreatureTypeMonster && cc.type != Proto::CreatureTypePlayer)
            continue;

        if (cc.id == localPlayerId)
            continue;

        if (cc.healthPercent <= 0)
            continue;

        for (const auto& t : transformedOffsets) {
            const Position targetPos = centerPos + t;
            if (cc.pos == targetPos) {
                count++;
                break;
            }
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    static int callCount = 0;
    static long long totalDuration = 0;
    callCount++;
    totalDuration += duration;

    if (callCount >= 100) {
        g_logger.info(fmt::format("[BotHelper] CreatureCache::getEnemiesInArea benchmark: avg {}us over 100 calls (last: {}us)", totalDuration / 100, duration));
        callCount = 0;
        totalDuration = 0;
    }

    return count;
}
