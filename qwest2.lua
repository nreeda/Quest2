-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
-- Determines proximity between two points.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Evaluates if it's beneficial to engage in combat with another player.
function shouldEngage(player, targetState)
    -- Compare player stats and decide whether to engage
    return player.energy > targetState.energy and player.health > targetState.health
end

-- Strategically decides on the next move based on health, proximity, energy, and items.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange, targetState = false, nil
  local healthThreshold = 30 -- Set a health threshold for defensive action
  local energyThreshold = 10 -- Set an energy threshold to maintain for defense
  local escapeDirection = "Up" -- Default escape direction

  -- Check if any target is within attack range and if it's beneficial to engage
  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 3) then
          if shouldEngage(player, state) then
              targetInRange = true
              targetState = state
              break
          else
              -- Choose an escape direction if the target is stronger
              escapeDirection = "Down"
          end
      end
  end

  -- Decide on the next action based on player's health and energy
  if player.health <= healthThreshold or player.energy <= energyThreshold then
    print("Low health or energy. Taking defensive measures.")
    -- Add your defensive strategy here, possibly moving towards health or energy pickups
  elseif targetInRange then
    print("Player in range and conditions favorable. Attacking.")
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(math.min(player.energy, 20))}) -- Attack with limited energy
  else
    print("No favorable targets. Moving strategically.")
    -- Move towards items or escape if a stronger player is nearby
    if targetState then
        ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = escapeDirection})
    else
        -- Add your movement strategy here, possibly towards items or advantageous positions
    end
  end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to strategically respond when hit by another player.
Handlers.add(
  "StrategicResponse",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
      local playerState = LatestGameState.Players[ao.id]
      local playerHealth = playerState.health
      local playerEnergy = playerState.energy

      -- Define thresholds for health and energy
      local healthThreshold = 50
      local energyThreshold = 20

      if playerHealth == undefined or playerEnergy == undefined then
        print("Unable to read player stats.")
        ao.send({Target = Game, Action = "Response-Failed", Reason = "Unable to read player stats."})
      elseif playerHealth <= healthThreshold then
        print("Health is low, choosing to defend.")
        ao.send({Target = Game, Action = "PlayerDefend", Player = ao.id})
      elseif playerEnergy <= energyThreshold then
        print("Energy is low, conserving for defense.")
        ao.send({Target = Game, Action = "Conserve-Energy", Player = ao.id})
      else
        print("Health and energy sufficient, returning attack.")
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(math.min(playerEnergy, 10))})
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
  end
)
