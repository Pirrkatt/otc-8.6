#include "stats.h"
#include <fstream>
#include <sstream>
#include <iomanip>
#include <map>
#include <framework/stdext/time.h>
#include <framework/ui/uiwidget.h>
#include <framework/ui/ui.h>

Stats g_stats;

AutoStatRecursive* AutoStatRecursive::activeStat = nullptr;

void Stats::add(int type, Stat* stat) {
    if (type < 0 || type > STATS_LAST)
        return;

    auto it = stats[type].data.emplace(stat->description, StatsData(0, 0, stat->extraDescription)).first;
    it->second.calls += 1;
    it->second.executionTime += stat->executionTime;

    if (stat->executionTime > 1000) {
        if (stats[type].slow.size() > 10000) {
            delete stats[type].slow.front();
            stats[type].slow.pop_front();
        }
        stats[type].slow.push_back(stat);
    } else
        delete stat;
}

std::string Stats::get(int type, int limit, bool pretty) {
    if (type < 0 || type > STATS_LAST)
        return "";

    std::multimap<uint64_t, StatsMap::const_iterator> sorted_stats;
    
    uint64_t total_time = 0;
    uint64_t time_from_start = (stdext::micros() - stats[type].start);

    for (auto it = stats[type].data.cbegin(); it != stats[type].data.cend(); ++it) {
        sorted_stats.emplace(it->second.executionTime, it);
        total_time += it->second.executionTime;
    }

    if (total_time == 0 || time_from_start == 0)
        return "";

    std::stringstream ret;

    int i = 0;
    if (pretty)
        ret << "Function" << std::setw(42) << "Calls" << std::setw(10) << "Time (ms)" << std::setw(10) << "Time (%)" << std::setw(10) << "Cpu (%)" << "\n";
    else
        ret << "Stats|" << type << "|" << limit << "|" << stdext::micros() << "|" << total_time << "|" << time_from_start << "\n";

    for (auto it = sorted_stats.rbegin(); it != sorted_stats.rend(); ++it) {
        if (i++ > limit)
            break;
        if (pretty) {
            std::string name = it->second->first.substr(0, 45);
            ret << name << std::setw(50 - name.size()) << it->second->second.calls << std::setw(10) << (it->second->second.executionTime / 1000)
                << std::setw(10) << ((it->second->second.executionTime * 100) / (total_time)) << std::setw(10) << ((it->second->second.executionTime * 100) / (time_from_start)) << "\n";
        } else {
            ret << it->second->first << "|" << it->second->second.calls << "|" << it->second->second.executionTime << "\n";
        }
    }

    return ret.str();
}

void Stats::clear(int type) {
    if (type < 0 || type > STATS_LAST)
        return;
    stats[type].start = stdext::micros();
    stats[type].data.clear();
}

void Stats::clearAll() {
    for (int i = 0; i <= STATS_LAST; ++i) {
        stats[i].data.clear();
        stats[i].slow.clear();
    }
    resetSleepTime();
}

std::string Stats::getSlow(int type, int limit, unsigned int minTime, bool pretty) {
    if (type < 0 || type > STATS_LAST)
        return "";

    std::stringstream ret;

    int i = 0;
    if (pretty)
        ret << "Function" << std::setw(42) << "Time (ms)" << std::setw(20) << "Extra description" << "\n";
    else
        ret << "Slow|" << type << "|" << limit << "|" << minTime << "|" << stdext::micros() << "\n";

    minTime *= 1000;

    for (auto it = stats[type].slow.rbegin(); it != stats[type].slow.rend(); ++it) {
        if ((*it)->executionTime < (minTime))
            continue;
        if (i++ > limit)
            break;
        if (pretty) {
            std::string name = (*it)->description.substr(0, 45);
            ret << name << std::setw(50 - name.size()) << (*it)->executionTime / 1000 << std::setw(20) << (*it)->extraDescription << "\n";
        } else {
            ret << (*it)->description << "|" << (*it)->executionTime << "|" << (*it)->extraDescription << "\n";
        }
    }

    return ret.str();
}

void Stats::clearSlow(int type) {
    if (type < 0 || type > STATS_LAST)
        return;
    for (auto& stat : stats[type].slow)
        delete stat;
    stats[type].slow.clear();
}


void Stats::addWidget(UIWidget* widget)
{
    createdWidgets += 1;
    widgets.insert(widget);
}

void Stats::removeWidget(UIWidget* widget)
{
    destroyedWidgets += 1;
    widgets.erase(widget);
}

struct WidgetTreeNode {
    UIWidgetPtr widget;
    int children_count;
    std::list<WidgetTreeNode> children;
};

void collectWidgets(WidgetTreeNode& node)
{
    node.widget->setRootChild(true);
    node.children_count = node.widget->getChildren().size();
    for (auto& child : node.widget->getChildren()) {
        node.children.push_back(WidgetTreeNode { child, 0, {} });
        collectWidgets(node.children.back());
        node.children_count += node.children.back().children_count;
    }
}

void printNode(std::stringstream& ret, WidgetTreeNode& node, int depth, int limit, bool pretty)
{
    if (depth >= limit || node.children_count < 50) return;
    ret << std::string(depth, '-') << node.widget->getId() << "|" << node.children_count << "\n";
    for (auto& child : node.children) {
        printNode(ret, child, depth + 1, limit, pretty);
    }
}

std::string Stats::getWidgetsInfo(int limit, bool pretty)
{
    int unusedWidgets = 0;
    // let's find invalid widgets
    for (auto& w : widgets) {
        w->setRootChild(false);
    }

    WidgetTreeNode node{ g_ui.getRootWidget() , 0, {} };
    collectWidgets(node);
    
    std::map<std::string, std::pair<int, int>> unusedWidgetsMap;
    std::map<std::string, std::pair<int, int>> allWidgetsMap;

    for (auto& w : widgets) {
        if (!w->isRootChild()) {
            unusedWidgets += 1;
            auto it = unusedWidgetsMap.emplace(w->getSource(), std::make_pair(0, 0)).first;
            it->second.first += 1;
            it->second.second += w->getUseCount();
        }
        auto it = allWidgetsMap.emplace(w->getSource(), std::make_pair(0, 0)).first;
        it->second.first += 1;
        it->second.second += w->getUseCount();
    }

    std::stringstream ret;
    if (pretty)
        ret << "Widgets: " << (createdWidgets - destroyedWidgets) << " (" << destroyedWidgets << "/" << createdWidgets << "/" << unusedWidgets << ")\n";
    else
        ret << (createdWidgets - destroyedWidgets) << "|" << destroyedWidgets << "|" << createdWidgets << "|" << unusedWidgets << "\n";
    if (pretty)
        ret << "Textures: " << (createdTextures - destroyedTextures) << " (" << destroyedTextures << "/" << createdTextures << ")\n";
    else
        ret << (createdTextures - destroyedTextures) << "|" << destroyedTextures << "|" << createdTextures << "\n";
    
    ret << "Active widgets (Widget|Childerns)" << "\n";

    printNode(ret, node, 0, limit, pretty);

    if (pretty) {
        ret << "\n\n" << "All Widgets (Source|Widgets|UseCount)" << "\n\n";
    } else {
        ret << "AllWidgets|Source|Widgets|UseCount" << "\n";
    }

    int i = 0;
    std::multimap<int, std::pair<std::string, int>> allWidgetsMapSorted;
    for (auto& it : allWidgetsMap) {
        if (it.second.first > 20) {
            allWidgetsMapSorted.emplace(it.second.first, std::make_pair(it.first, it.second.second));
            if (++i >= limit) {
                break;
            }
        }
    }

    for (auto it = allWidgetsMapSorted.rbegin(); it != allWidgetsMapSorted.rend(); ++it) {
        ret << it->second.first << "|" << it->first << "|" << it->second.second << "\n";
    }

    if (pretty) {
        ret << "\n\n" << "Unused Widgets (Source|Widgets|UseCount)" << "\n\n";
    } else {
        ret << "UnusedWidgets|Source|Widgets|UseCount" << "\n";
    }

    i = 0;
    std::multimap<int, std::pair<std::string, int>> unusedWidgetsMapSorted;
    for (auto& it : unusedWidgetsMap) {
        unusedWidgetsMapSorted.emplace(it.second.first, std::make_pair(it.first, it.second.second));
        if (++i >= limit) {
            break;
        }
    }

    for (auto it = unusedWidgetsMapSorted.rbegin(); it != unusedWidgetsMapSorted.rend(); ++it) {
        ret << it->second.first << "|" << it->first << "|" << it->second.second << "\n";
    }

    return ret.str();
}
