-- Whole thing is still at very early stage of development, a lot might and possibly
-- will change. Currently whole thing is limited to sort of original drifting mode
-- level. Observe things that happen, draw some extra UI, score user,
-- decide when session ends.

-- This mode in particular is meant for Track Day with AI Flood on large tracks. Set
-- AIs to draw some slow cars, get yourself that Red Bull monstrousity and try to
-- score some points.

-- Key points for future:
-- • Integration with CM’s Quick Drive section, with settings and everything;
-- • These modes might need to be able to force certain CSP parameters — here, for example,
--   it should be AI flood parameters;
-- • To ensure competitiveness, they might also need to collect some data, verify integrity
--   and possibly record short replays?
-- • Remote future: control scene, AIs, spawn extra geometry and so on.

-- Event configuration:
local requiredSpeed = 60


-- This function is called before event activates. Once it returns true, it’ll run:
function script.prepare(dt)
    ac.debug("speed", ac.getCarState(1).speedKmh)
    return ac.getCarState(1).speedKmh > 60
end

-- Event state:
local timePassed = 0
local totalScore = 0
local comboMeter = 1
local comboColor = 0
local highestScore = 0
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0

function script.update(dt)
    if timePassed == 0 then
        addMessage("Let’s go!", 0)
    end

    local player = ac.getCarState(1)
    if player.engineLifeLeft < 1 then
        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
        end
        totalScore = 0
        comboMeter = 1
        return
    end

    timePassed = timePassed + dt

    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    local sim = ac.getSimState()
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end

    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
        end
        addMessage("Car is outside", -1)
        wheelsWarningTimeout = 60
    end

    if player.speedKmh < requiredSpeed then
        if dangerouslySlowTimer > 3 then
            if totalScore > highestScore then
                highestScore = math.floor(totalScore)
            end
            totalScore = 0
            comboMeter = 1
        else
            if dangerouslySlowTimer == 0 then
                addMessage("Too slow!", -1)
            end
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        return
    else
        dangerouslySlowTimer = 0
    end

    for i = 1, ac.getSimState().carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]

        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false

                if not state.nearMiss and car.pos:closerToThan(player.pos, 3) then
                    state.nearMiss = true

                    if car.pos:closerToThan(player.pos, 2.5) then
                        comboMeter = comboMeter + 3
                        addMessage("Very close near miss!", 1)
                    else
                        comboMeter = comboMeter + 1
                        addMessage("Near miss: bonus combo", 0)
                    end
                end
            end

            if car.collidedWith == 0 then
                addMessage("Collision", -1)
                state.collided = true

                if totalScore > highestScore then
                    highestScore = math.floor(totalScore)
                end
                totalScore = 0
                comboMeter = 1
            end

            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot, posDot)
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    totalScore = totalScore + math.ceil(10 * comboMeter)
                    comboMeter = comboMeter + 1
                    comboColor = comboColor + 90
                    addMessage("Overtake", comboMeter > 20 and 1 or 0)
                    state.overtaken = true
                end
            end
        else
            state.maxPosDot = -1
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMiss = false
        end
    end
end

-- For various reasons, this is the most questionable part, some UI. I don’t really like
-- this way though. So, yeah, still thinking about the best way to do it.
local messages = {}
local glitter = {}
local glitterCount = 0

function addMessage(text, mood)
    for i = math.min(#messages + 1, 4), 2, -1 do
        messages[i] = messages[i - 1]
        messages[i].targetPos = i
    end
    messages[1] = {text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood}
    if mood == 1 then
        for i = 1, 60 do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(80, 140) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

local function updateMessages(dt)
    comboColor = comboColor + dt * 10 * comboMeter
    if comboColor > 360 then
        comboColor = comboColor - 360
    end
    for i = 1, #messages do
        local m = messages[i]
        m.age = m.age + dt
        m.currentPos = math.applyLag(m.currentPos, m.targetPos, 0.8, dt)
    end
    for i = glitterCount, 1, -1 do
        local g = glitter[i]
        g.pos:add(g.velocity)
        g.velocity.y = g.velocity.y + 0.02
        g.life = g.life - dt
        g.color.mult = math.saturate(g.life * 4)
        if g.life < 0 then
            if i < glitterCount then
                glitter[i] = glitter[glitterCount]
            end
            glitterCount = glitterCount - 1
        end
    end
    if comboMeter > 10 and math.random() > 0.98 then
        for i = 1, math.floor(comboMeter) do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(195, 75) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

local speedWarning = 0

function script.drawUI()
    local uiState = ac.getUiState()
    updateMessages(uiState.dt)

    local player = ac.getCarState(1)
    local speedRelative = math.saturate(math.floor(player.speedKmh) / requiredSpeed)
    speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

    -- Modern color palette
    local colorBg = rgbm(0.08, 0.08, 0.1, 0.85)
    local colorCard = rgbm(0.15, 0.15, 0.18, 0.9)
    local colorAccent = rgbm.new(hsv(comboColor, 0.8, 1):rgb(), 1)
    local colorText = rgbm(0.95, 0.95, 0.95, 1)
    local colorPositive = rgbm(0.2, 0.8, 0.4, 1)
    local colorNegative = rgbm(0.9, 0.3, 0.3, 1)
    local colorWarning = rgbm(0.9, 0.6, 0.2, 1)

    -- Fixed window size since we can't get it dynamically
    local windowSize = vec2(300, 220)
    local windowPos = vec2(20, 20)

    -- Main container
    ui.beginTransparentWindow("overtakeScore", windowPos, windowSize)
    
    -- Background with rounded corners
    ui.drawRectFilled(vec2(0, 0), windowSize, colorBg, 12)
    ui.drawRect(vec2(0, 0), windowSize, rgbm(0.3, 0.3, 0.35, 0.3), 1, 12)

    -- Header
    ui.pushFont(ui.Font.Title)
    ui.textColored("OVERTAKE", colorAccent)
    ui.popFont()
    
    -- Score cards - using fixed positions based on window size
    ui.offsetCursorY(10)
    
    -- Current score card (left side)
    local cardWidth = (windowSize.x - 10) / 2
    local cardHeight = 70
    
    ui.drawRectFilled(vec2(0, ui.getCursorY()), vec2(cardWidth, cardHeight), colorCard, 8)
    ui.drawRect(vec2(0, ui.getCursorY()), vec2(cardWidth, cardHeight), rgbm(0.3, 0.3, 0.35, 0.5), 1, 8)
    ui.setCursor(vec2(10, ui.getCursorY() + 10))
    ui.pushFont(ui.Font.Small)
    ui.textColored("CURRENT SCORE", rgbm(0.7, 0.7, 0.7, 1))
    ui.popFont()
    ui.setCursor(vec2(10, ui.getCursorY() + 5))
    ui.pushFont(ui.Font.Huge)
    ui.textColored(string.format("%06d", totalScore), colorText)
    ui.popFont()
    
    -- Combo card (right side)
    ui.setCursor(vec2(cardWidth + 10, 30))
    ui.drawRectFilled(vec2(cardWidth + 10, 30), vec2(windowSize.x, 30 + cardHeight), colorCard, 8)
    ui.drawRect(vec2(cardWidth + 10, 30), vec2(windowSize.x, 30 + cardHeight), rgbm(0.3, 0.3, 0.35, 0.5), 1, 8)
    ui.setCursor(vec2(cardWidth + 20, 40))
    ui.pushFont(ui.Font.Small)
    ui.textColored("COMBO MULTIPLIER", rgbm(0.7, 0.7, 0.7, 1))
    ui.popFont()
    ui.setCursor(vec2(cardWidth + 20, 45))
    ui.pushFont(ui.Font.Huge)
    ui.beginRotation()
    ui.textColored(string.format("%.1fX", comboMeter), colorAccent)
    if comboMeter > 20 then
        ui.endRotation(math.sin(comboMeter / 180 * 3141.5) * 3 * math.lerpInvSat(comboMeter, 20, 30) + 90)
    end
    ui.popFont()
    
    -- Speed warning (below cards)
    ui.offsetCursorY(80)
    if speedWarning > 0.1 then
        -- ui.drawRectFilled(vec2(0, ui.getCursorY()), vec2(windowSize.x, 30), rgbm(0.15, 0.1, 0.05, 0.7), 6)
        ui.drawRect(vec2(0, ui.getCursorY()), vec2(windowSize.x, 30), rgbm(0.8, 0.4, 0.1, 0.5), 1, 6)
        ui.setCursor(vec2(10, ui.getCursorY() + 7))
        ui.pushFont(ui.Font.Main)
        ui.textColored("SPEED TOO LOW!", colorWarning)
        ui.popFont()
        
        -- Speed progress bar
        local progress = math.min(player.speedKmh/requiredSpeed, 1)
        local barWidth = windowSize.x - 20
        -- ui.drawRectFilled(vec2(10, ui.getCursorY() + 15), vec2(10 + barWidth, ui.getCursorY() + 20), rgbm(0.2, 0.2, 0.2, 1), 3)
        -- ui.drawRectFilled(vec2(10, ui.getCursorY() + 15), vec2(10 + barWidth * progress, ui.getCursorY() + 20), colorWarning, 3)
        ui.drawText(vec2(windowSize.x - 60, ui.getCursorY() + 12), string.format("%d/%d km/h", math.floor(player.speedKmh), requiredSpeed), rgbm(0.9, 0.9, 0.9, 1))
    end
    
    -- Messages area (bottom section)
    ui.offsetCursorY(40)
    local messagesHeight = 80
    ui.drawRectFilled(vec2(0, ui.getCursorY()), vec2(windowSize.x, ui.getCursorY() + messagesHeight), rgbm(0.1, 0.1, 0.12, 0.7), 8)
    ui.drawRect(vec2(0, ui.getCursorY()), vec2(windowSize.x, ui.getCursorY() + messagesHeight), rgbm(0.3, 0.3, 0.35, 0.3), 1, 8)
    
    local messageStartPos = ui.getCursor() + vec2(10, 10)
    for i = 1, #messages do
        local m = messages[i]
        local fade = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
        local offsetX = math.saturate(1 - m.age * 5) ^ 2 * 15
        
        ui.setCursor(messageStartPos + vec2(offsetX, (m.currentPos - 1) * 18))
        
        local messageColor = m.mood == 1 and colorPositive or m.mood == -1 and colorNegative or colorText
        messageColor.mult = fade
        
        ui.pushFont(ui.Font.Main)
        ui.textColored(m.text, messageColor)
        ui.popFont()
    end
    
    -- Glitter effects
    for i = 1, glitterCount do
        local g = glitter[i]
        if g ~= nil then
            ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
        end
    end

    -- Highest score at bottom
    ui.setCursor(vec2(10, windowSize.y - 20))
    ui.pushFont(ui.Font.Small)
    ui.textColored("HIGH SCORE: " .. string.format("%06d", highestScore), rgbm(0.7, 0.7, 0.7, 1))
    ui.popFont()

    ui.endTransparentWindow()
end