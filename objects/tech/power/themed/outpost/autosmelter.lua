--

require "/lib/stardust/prefabs.lua"
require "/lib/stardust/power.lua"

nullItem = { name = "", count = 0, parameters = {} }

function init()
  slotConfig = config.getParameter("slotConfig")
  smelterConfig = config.getParameter("smelterConfig")
  recipes = config.getParameter("recipes")

  local cfg = config.getParameter("batteryStats")
  battery = prefabs.power.battery(cfg.capacity, cfg.ioRate):hookUp():autoSave()
  storage.smelting = storage.smelting or {}
  smelting = storage.smelting -- alias
  smelting.remaining = smelting.remaining or 0
  smelting.smeltTime = smelting.smeltTime or 1
  smelting.item = smelting.item or nullItem
  smelting.results = smelting.results or {}

  message.setHandler("uiSyncRequest", uiSyncRequest)

  rng = sb.makeRandomSource(os.time())
end

function update()
  -- handle fueling
  if smelting.remaining > 0 then
    if battery:consume(smelterConfig.powerPerTick) then
      smelting.remaining = smelting.remaining - 1
    end
  else
    script.setUpdateDelta(30)
    local remainingOutput = {}

    -- attempt to stack result items into output slots
    for _,item in pairs(smelting.results) do
      local remaining = { name = item.name, count = item.count, parameters = item.parameters }
      -- loop through output slots and attempt to place
      for _,slot in pairs(slotConfig.output) do
        remaining = world.containerPutItemsAt(entity.id(), remaining, slot - 1) or {}
        if not remaining.count or remaining.count <= 0 then break end
      end
      if remaining.count and remaining.count > 0 then remainingOutput[#remainingOutput+1] = remaining end
    end

    if #remainingOutput > 0 then
      smelting.results = remainingOutput
    else
      smelting.item = nullItem
      smelting.results = {}

      -- take item from input slots that fits a recipe
      local containerItems = world.containerItems(entity.id())
      for _,slot in pairs(slotConfig.input) do
        if containerItems[slot] then
          local item = containerItems[slot]

          recipe = recipes[item.name]
          if recipe then
            recipe.count = recipe.count or 1 -- set default if missing

            if item.count >= recipe.count then
              -- match! take item
              smelting.item = world.containerTakeNumItemsAt(entity.id(), slot-1, recipe.count)
              smelting.remaining = recipe.time or smelterConfig.ticksPerItem
              smelting.smeltTime = smelting.remaining

              -- determine results
              local results = {}
              smelting.results = results
              if recipe.result then
                local res = recipe.result
                if res.name then res = { res } end -- arrayize if single entry
                for _,r in pairs(res) do
                  if rng:randf() < (r.chance or 1) then -- chance passed or no chance specified
                    results[#results+1] = { name = r.name, count = r.count or 1, parameters = r.parameters or {} }
                  end
                end
              end

              script.setUpdateDelta(1) -- resume full tickrate operation
              break -- done here
            end
          end
        end
      end
    end
  end

  -- and handle animation states
  if smelting.remaining > 0 then
    object.setAnimationParameter("lit", 1)
  else
    object.setAnimationParameter("lit", 0)
  end
end

function uiSyncRequest(msg, isLocal, ...)
  return {
    batteryStats = { energy = battery.state.energy, capacity = battery.capacity },
    smelting = smelting
  }
end







--
