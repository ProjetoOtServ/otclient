"use client"

import { useState } from "react"
import { Check, Info, Plus, X, ChevronLeft, ChevronRight } from "lucide-react"

// Custom checkbox component styled like OTClient
function OTCheckbox({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label?: string }) {
  return (
    <label className="flex items-center gap-1.5 cursor-pointer select-none">
      <div
        onClick={() => onChange(!checked)}
        className={`w-4 h-4 border border-zinc-500 bg-zinc-700 flex items-center justify-center ${checked ? "text-green-400" : "text-transparent"}`}
      >
        {checked && <Check className="w-3 h-3" strokeWidth={3} />}
      </div>
      {label && <span className="text-zinc-200 text-sm">{label}</span>}
    </label>
  )
}

// Spinner/Select component
function OTSpinner({ value, suffix = "%" }: { value: string | number; suffix?: string }) {
  return (
    <div className="flex items-center border border-zinc-600 bg-zinc-800">
      <button className="px-1 py-0.5 text-zinc-400 hover:text-zinc-200 border-r border-zinc-600">
        <ChevronLeft className="w-3 h-3" />
      </button>
      <span className="px-2 py-0.5 text-sm text-zinc-200 min-w-[40px] text-center">
        {value}{suffix}
      </span>
      <button className="px-1 py-0.5 text-zinc-400 hover:text-zinc-200 border-l border-zinc-600">
        <ChevronRight className="w-3 h-3" />
      </button>
    </div>
  )
}

// Select/Dropdown component
function OTSelect({ value, options }: { value: string; options: string[] }) {
  return (
    <div className="flex items-center border border-zinc-600 bg-zinc-800">
      <span className="px-2 py-0.5 text-sm text-zinc-200 min-w-[40px] text-center">{value}</span>
      <button className="px-1 py-0.5 text-zinc-400 hover:text-zinc-200 border-l border-zinc-600">
        <ChevronRight className="w-3 h-3 rotate-90" />
      </button>
    </div>
  )
}

// Info button
function InfoButton() {
  return (
    <button className="w-5 h-5 rounded-full border border-zinc-500 text-zinc-400 flex items-center justify-center hover:text-zinc-200">
      <Info className="w-3 h-3" />
    </button>
  )
}

// Section panel
function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border border-zinc-600 border-t-zinc-500">
      <div className="bg-zinc-700/80 border-b border-zinc-600 px-3 py-1.5 text-center">
        <span className="text-zinc-200 text-sm font-medium">{title}</span>
      </div>
      <div className="p-3 bg-zinc-800/50">{children}</div>
    </div>
  )
}

// Button component
function OTButton({ children, variant = "default" }: { children: React.ReactNode; variant?: "default" | "primary" }) {
  const baseClass = "px-3 py-1 text-sm border transition-colors"
  const variants = {
    default: "bg-zinc-700 border-zinc-600 text-zinc-200 hover:bg-zinc-600",
    primary: "bg-blue-600 border-blue-500 text-white hover:bg-blue-500",
  }
  return <button className={`${baseClass} ${variants[variant]}`}>{children}</button>
}

// Spell/Item icon placeholder
function IconSlot({ icon, color = "cyan" }: { icon?: string; color?: string }) {
  const colors: Record<string, string> = {
    cyan: "from-cyan-400/30 to-cyan-600/30 border-cyan-500/50",
    purple: "from-purple-400/30 to-purple-600/30 border-purple-500/50",
    pink: "from-pink-400/30 to-pink-600/30 border-pink-500/50",
    green: "from-green-400/30 to-green-600/30 border-green-500/50",
    red: "from-red-400/30 to-red-600/30 border-red-500/50",
    yellow: "from-yellow-400/30 to-yellow-600/30 border-yellow-500/50",
  }
  return (
    <div className={`w-10 h-10 bg-gradient-to-br ${colors[color]} border border-zinc-600 flex items-center justify-center`}>
      {icon && <span className="text-lg">{icon}</span>}
    </div>
  )
}

// Tab icons
function TabIcon({ active, children }: { active?: boolean; children: React.ReactNode }) {
  return (
    <div
      className={`w-10 h-10 flex items-center justify-center cursor-pointer transition-colors ${active ? "bg-zinc-700 border border-zinc-500" : "bg-zinc-800/50 border border-transparent hover:bg-zinc-700/50"}`}
    >
      {children}
    </div>
  )
}

// Tools Tab Content
function ToolsTab() {
  const [manaTraining, setManaTraining] = useState(true)
  const [exerciseTraining, setExerciseTraining] = useState(false)
  const [autoHaste, setAutoHaste] = useState(false)
  const [pzCast, setPzCast] = useState(true)
  const [changeGold, setChangeGold] = useState(true)
  const [autoEatFood, setAutoEatFood] = useState(true)
  const [autoReconnect, setAutoReconnect] = useState(false)

  return (
    <Section title="Tools Helper">
      <div className="grid grid-cols-2 gap-4">
        {/* Mana Training */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-zinc-300 text-sm font-medium">Mana Training</span>
          </div>
          <div className="flex items-center gap-2">
            <IconSlot color="green" />
            <div className="space-y-1">
              <OTCheckbox checked={manaTraining} onChange={setManaTraining} label="Enable" />
              <div className="flex items-center gap-1">
                <OTSpinner value={90} />
                <InfoButton />
              </div>
            </div>
          </div>
        </div>

        {/* Auto Haste */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-zinc-300 text-sm font-medium">Auto Haste</span>
          </div>
          <div className="flex items-center gap-2">
            <IconSlot color="cyan" />
            <div className="space-y-1">
              <OTCheckbox checked={autoHaste} onChange={setAutoHaste} label="Enable" />
              <OTCheckbox checked={pzCast} onChange={setPzCast} label="PZ Cast" />
            </div>
          </div>
        </div>

        {/* Exercise Training */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-zinc-300 text-sm font-medium">Exercise Training</span>
          </div>
          <div className="flex items-center gap-2">
            <IconSlot color="yellow" />
            <div className="space-y-1">
              <OTCheckbox checked={exerciseTraining} onChange={setExerciseTraining} label="Enable" />
              <div className="flex items-center gap-1">
                <OTSelect value="" options={["Sword", "Axe", "Club"]} />
                <InfoButton />
              </div>
            </div>
          </div>
        </div>

        {/* Others Tools */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-zinc-300 text-sm font-medium">Others Tools</span>
            <InfoButton />
          </div>
          <div className="space-y-1">
            <OTCheckbox checked={changeGold} onChange={setChangeGold} label="Change Gold" />
            <OTCheckbox checked={autoEatFood} onChange={setAutoEatFood} label="Auto Eat Food" />
            <OTCheckbox checked={autoReconnect} onChange={setAutoReconnect} label="Auto Reconnect" />
          </div>
        </div>
      </div>
    </Section>
  )
}

// Healing Tab Content
function HealingTab() {
  return (
    <div className="space-y-3">
      <Section title="Auto Healing Helper">
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <span className="text-zinc-300 text-sm font-medium">Spell Healing</span>
            <div className="flex items-center gap-2">
              <IconSlot color="cyan" />
              <OTSpinner value={80} />
              <InfoButton />
            </div>
            <div className="flex items-center gap-2">
              <IconSlot color="red" />
              <OTSpinner value={99} />
              <InfoButton />
            </div>
          </div>
          <div className="space-y-2">
            <span className="text-zinc-300 text-sm font-medium">Potion Healing</span>
            <div className="flex items-center gap-2">
              <IconSlot color="pink" />
              <OTSpinner value={60} />
              <InfoButton />
            </div>
            <div className="flex items-center gap-2">
              <IconSlot color="pink" />
              <OTSpinner value={30} />
              <InfoButton />
            </div>
          </div>
        </div>
      </Section>

      <Section title="Friend Healing Helper">
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <div className="flex items-center gap-1">
              <span className="text-zinc-300 text-sm">Select a Friend</span>
              <InfoButton />
            </div>
            <div className="border border-zinc-600 bg-zinc-900/50 h-20 overflow-auto" />
          </div>
          <div className="space-y-2">
            <span className="text-zinc-300 text-sm">Heal Friend List</span>
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <button className="w-6 h-6 bg-zinc-700 border border-zinc-600 flex items-center justify-center text-zinc-400 hover:text-zinc-200">
                  <Plus className="w-4 h-4" />
                </button>
                <OTCheckbox checked={false} onChange={() => {}} label="Enable Sio" />
                <OTSpinner value={99} />
                <InfoButton />
              </div>
              <div className="flex items-center gap-2">
                <button className="w-6 h-6 bg-zinc-700 border border-zinc-600 flex items-center justify-center text-zinc-400 hover:text-zinc-200">
                  <Plus className="w-4 h-4" />
                </button>
                <OTCheckbox checked={false} onChange={() => {}} label="Enable Sio" />
                <OTSpinner value={99} />
                <InfoButton />
              </div>
            </div>
          </div>
        </div>
      </Section>

      <Section title="Exura Gran Sio Helper">
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <div className="flex items-center gap-1">
              <span className="text-zinc-300 text-sm">Select a Friend</span>
              <InfoButton />
            </div>
            <div className="border border-zinc-600 bg-zinc-900/50 h-16 overflow-auto" />
          </div>
          <div className="space-y-2">
            <span className="text-zinc-300 text-sm">Heal Friend List</span>
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <button className="w-6 h-6 bg-zinc-700 border border-zinc-600 flex items-center justify-center text-zinc-400 hover:text-zinc-200">
                  <Plus className="w-4 h-4" />
                </button>
                <OTCheckbox checked={false} onChange={() => {}} label="Enable" />
                <OTSpinner value={99} />
                <InfoButton />
              </div>
            </div>
          </div>
        </div>
      </Section>
    </div>
  )
}

// RTCaster Tab Content
function RTCasterTab() {
  const [autoTarget, setAutoTarget] = useState(false)
  const [enableShooter, setEnableShooter] = useState(false)

  return (
    <div className="space-y-3">
      {/* Presets */}
      <div className="border border-zinc-600 p-3 bg-zinc-800/50">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <span className="text-zinc-300 text-sm">Presets:</span>
            <OTButton>Set Key</OTButton>
            <InfoButton />
          </div>
          <div className="flex items-center gap-2">
            <OTButton>Rename Preset</OTButton>
            <OTButton variant="primary">New Preset</OTButton>
          </div>
        </div>
        <div className="flex items-center gap-2 mt-2">
          <OTSelect value="Energy" options={["Energy", "Fire", "Ice"]} />
          <button className="text-red-500 hover:text-red-400">
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      <Section title="Spell Shooter Helper">
        <div className="space-y-2">
          <div className="grid grid-cols-4 gap-2 text-center text-xs text-zinc-400 mb-2">
            <span>Spell</span>
            <span>Mana %</span>
            <span>Creatures</span>
            <span>Priority</span>
          </div>
          {[
            { color: "cyan", mana: 10, creatures: "6+", priority: "1st" },
            { color: "cyan", mana: 5, creatures: "3+", priority: "1st" },
            { color: "pink", mana: 1, creatures: "1+", priority: "1st" },
          ].map((spell, i) => (
            <div key={i} className="grid grid-cols-4 gap-2 items-center">
              <IconSlot color={spell.color} />
              <OTSpinner value={spell.mana} />
              <OTSelect value={spell.creatures} options={["1+", "2+", "3+", "6+"]} />
              <OTSelect value={spell.priority} options={["1st", "2nd", "3rd"]} />
            </div>
          ))}
        </div>
      </Section>

      <Section title="Rune Shooter Helper">
        <div className="space-y-2">
          <div className="grid grid-cols-3 gap-2 text-center text-xs text-zinc-400 mb-2">
            <span>Rune</span>
            <span>Creatures</span>
            <span>Priority</span>
          </div>
          {[
            { color: "purple", creatures: "2+", priority: "2nd" },
            { color: "purple", creatures: "1+", priority: "5th" },
          ].map((rune, i) => (
            <div key={i} className="grid grid-cols-3 gap-2 items-center">
              <IconSlot color={rune.color} />
              <div className="flex items-center gap-1">
                <OTSelect value={rune.creatures} options={["1+", "2+"]} />
              </div>
              <div className="flex items-center gap-1">
                <OTSelect value={rune.priority} options={["1st", "2nd", "3rd", "5th"]} />
                <InfoButton />
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* Bottom controls */}
      <div className="space-y-2 border border-zinc-600 p-3 bg-zinc-800/50">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <OTCheckbox checked={autoTarget} onChange={setAutoTarget} label="Auto Target" />
            <OTSelect value="F" options={["F", "G", "H"]} />
            <InfoButton />
          </div>
          <OTButton>Set Key</OTButton>
        </div>
        <div className="flex items-center justify-between">
          <OTCheckbox checked={enableShooter} onChange={setEnableShooter} label="Enable Shooter Helper" />
          <OTButton>Set Key</OTButton>
        </div>
        <div className="flex items-center justify-between">
          <OTButton variant="primary">Set Key (Target/Shooter)</OTButton>
          <InfoButton />
        </div>
      </div>
    </div>
  )
}

// Main Interface
export default function OTBotInterface() {
  const [activeTab, setActiveTab] = useState<"tools" | "healing" | "caster">("tools")
  const [helperEnabled, setHelperEnabled] = useState(true)

  const tabs = [
    { id: "tools" as const, label: "Tools", emoji: "🎒" },
    { id: "healing" as const, label: "Healing", emoji: "❤️" },
    { id: "caster" as const, label: "RTCaster", emoji: "⚡" },
  ]

  return (
    <div className="min-h-screen bg-zinc-600 flex items-center justify-center p-4" style={{ backgroundImage: "url(\"data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23666' fill-opacity='0.15'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E\")" }}>
      <div className="w-full max-w-md">
        {/* Header/Logo Area */}
        <div className="flex justify-center mb-2">
          <div className="relative">
            <div className="w-32 h-24 bg-gradient-to-b from-yellow-600 to-yellow-800 border-4 border-yellow-500 rounded-t-lg flex items-center justify-center shadow-lg">
              <div className="text-4xl font-bold text-yellow-200 drop-shadow-lg" style={{ textShadow: "2px 2px 4px rgba(0,0,0,0.5)" }}>
                R
              </div>
            </div>
            {/* Decorative elements */}
            <div className="absolute -left-6 top-1/2 w-4 h-8 bg-red-600 border-2 border-red-400 rounded-full" />
            <div className="absolute -right-6 top-1/2 w-4 h-8 bg-purple-600 border-2 border-purple-400 rounded-full" />
          </div>
        </div>

        {/* Main Panel */}
        <div className="border-2 border-zinc-500 bg-zinc-800/90 shadow-2xl">
          {/* Tab Bar */}
          <div className="flex items-center gap-1 p-2 border-b border-zinc-600 bg-zinc-700/50">
            {tabs.map((tab) => (
              <TabIcon key={tab.id} active={activeTab === tab.id}>
                <button
                  onClick={() => setActiveTab(tab.id)}
                  className="w-full h-full flex items-center justify-center text-lg"
                  title={tab.label}
                >
                  {tab.emoji}
                </button>
              </TabIcon>
            ))}
            <div className="flex-1 px-3">
              <span className="text-zinc-200 text-sm font-medium">
                {tabs.find((t) => t.id === activeTab)?.label}
              </span>
            </div>
          </div>

          {/* Content Area */}
          <div className="p-3 max-h-[500px] overflow-y-auto">
            {activeTab === "tools" && <ToolsTab />}
            {activeTab === "healing" && <HealingTab />}
            {activeTab === "caster" && <RTCasterTab />}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between p-3 border-t border-zinc-600 bg-zinc-700/50">
            <div className="flex items-center gap-2">
              <span className="text-zinc-300 text-sm">Helper Status:</span>
              <span className={`text-sm font-medium ${helperEnabled ? "text-green-400" : "text-red-400"}`}>
                {helperEnabled ? "Enabled" : "Disabled"}
              </span>
              {helperEnabled && <Check className="w-4 h-4 text-green-400" />}
              <OTButton>Set Key</OTButton>
            </div>
            <div className="flex items-center gap-2">
              <OTButton>Helper Stats</OTButton>
              <OTButton>Close</OTButton>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
