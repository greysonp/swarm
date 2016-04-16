pico-8 cartridge // http://www.pico-8.com
version 5
__lua__
-- game objects
cursor = nil
beehive = nil
cam = nil -- need global position state for smoothing

-- collections
stage = {}
bees = {}
enemies = {}
anchors = {}
flowers = {}

-- constants
fps = 30
startbees = 10
stagewidth = 256
stageheight = 256
startlives = 3
minflowers = 4
camlag = .1 -- constant we use as 't' in low-pass filter calculation
beehive_layer = 1
anchor_layer = beehive_layer + 1
enemy_layer = anchor_layer + 1
bee_layer = enemy_layer + 1
cursor_layer = bee_layer + 1
hud_layer = cursor_layer + 1

-- other
time = 0
lives = 0
score = 0
screen = 0 -- 0 = title screen, 1 = game, 2 = game over
gameovertimer = 0
spawntimermaxorig = 10 * fps
spawntimermax = spawntimermaxorig
spawntimermin = 2 * fps
spawntimer = spawntimermax -- init to max so we'll spawn right away when the game starts

-- debug elements
flag = false
debugtext = nil

function _init()
  -- switch to 64x64 mode
  poke(0x5f2c, 3)
  cls()

  cam = {}
end

function _update()
  if screen == 0 then
    _updatetitle()
  elseif screen == 1 then
    _updategame()
  elseif screen == 2 then
    _updategameover()
  end
end

function _draw()
  if screen == 0 then
    _drawtitle()
  elseif screen == 1 then
    _drawgame()
  elseif screen == 2 then
    _drawgameover()
  end

  if flag then pset(cam.x + 63, cam.y, 8) end
  if debugtext != nil then
    print(debugtext, cam.x, cam.y + 59)
  end
end

function _initgame()
  -- clear all state
  stage = {}
  bees = {}
  enemies = {}
  anchors = {}
  flowers = {}
  time = 0
  lives = startlives
  score = 0
  gameovertimer = 0

  -- add cursor to the stage
  cursor = newcursor(115, 115)
  add(stage, cursor)

  -- init camera state
  cam = newvector(cursor.pos.x - 32, cursor.pos.y - 32)
  cam.width = 64
  cam.height = 64

  -- add beehive to the stage
  beehive = newbeehive(stagewidth/2, stageheight/2)
  add(stage, beehive)
  add(anchors, beehive)

  -- add hud to the stage
  add(stage, newbeecounter())
  add(stage, newlifecounter())
  add(stage, newscore())

  -- add flowers to the stage
  addflower(newflower(110, 110, 32))

  -- add bees to the stage
  for i = 1, startbees do
    local bee = newbee(random(beehive.pos.x - 5, beehive.pos.x + 5), random(beehive.pos.y - 5, beehive.pos.y + 5), beehive)
    addbee(bee)
  end
end

function _updatetitle()
  if btnp(1) or btnp(2) or btnp(3) or btnp(4) or btnp(5) or btnp(6) then
    _initgame()
    screen = 1
  end
end

function _updategame()
  time = (time + 1) % 32000

  -- clear out all of the cached bee data
  foreach(bees, function(bee)
    bee.closestbee =  nil
  end)

  -- update all of the object's positions
  foreach(stage, function(obj)
    obj:update()
    obj.pos.x += obj.vel.x
    obj.pos.y += obj.vel.y
  end)

  -- update the camera position
  local adjcursor = vsub(cursor.pos, newvector(32, 32))
  cam.x = cam.x * (1 - camlag) + adjcursor.x * camlag
  cam.y = cam.y * (1 - camlag) + adjcursor.y * camlag

  cam.x = max(0, cam.x)
  cam.x = min(stagewidth - cam.width, cam.x)
  cam.y = max(0, cam.y)
  cam.y = min(stageheight - cam.height, cam.y)

  camera(cam.x, cam.y)

  -- spawn enemies
  if not beehive.isfirst then
    spawntimermax = max(spawntimermaxorig - score, spawntimermin)
    spawntimer += 1
    if spawntimer > spawntimermax then
      spawnenemy()
      spawntimer = 0
    end
  end

  -- ensure a minimum number of flowers
  while count(flowers) < minflowers do
    spawnflower()
  end
end

function _updategameover()
  if gameovertimer > 30 then
    if btnp(1) or btnp(2) or btnp(3) or btnp(4) or btnp(5) or btnp(6) then screen = 0 end
  end
  gameovertimer += 1
end

function _drawtitle()
  cam.x = 0
  cam.y = 0
  camera(0, 0)

  map(34, 0, 0, 0, 8, 8)
  spr(192, 6, 5, 7, 3)
  spr(32, 5, 30)
  spr(33, 50, 50)
  spr(16, 27, 50)
  rectfill(30, 56, 31, 57, 0)
  print('press button', 9, 40, 7)
end

function _drawgame()
  -- draw map
  map(0, 0, 0, 0, stagewidth/8, stageheight/8)

  -- construct a mapping of each object to it's layer
  local layers = {}
  local maxlayer = 0
  for obj in all(stage) do
    if layers[obj.layer] == nil then layers[obj.layer] = {} end
    add(layers[obj.layer], obj)
    maxlayer = max(maxlayer, obj.layer)
  end

  -- draw all the object, layer by layer
  -- note: need 'maxlayer' because all(coll) only works with continuous arrays (we may have layer gaps)
  for i = 1, maxlayer do
    local layer = layers[i]
    for obj in all(layer) do
      obj:draw()
    end
  end
end

function _drawgameover()
  cam.x = 0
  cam.y = 0
  camera(0, 0)

  cls()
  printcenter('game over', 20, 7)
  printcenter('score: ' .. score, 35, 7)
end

function addbee(bee)
  add(bee.anchor.bees, bee)
  add(bees, bee)
  add(stage, bee)
end

function spawnenemy()
  local x = random(0, stagewidth)
  local y = random(0, stageheight)

  if x <= stagewidth/2 then x = -5
  else x = stagewidth + 5 end

  if y <= stageheight/2 then y = -5
  else y = stageheight + 5 end

  local enemy = nil
  if score < 80 then
    enemy = newenemy(x, y, 64)
  elseif score < 160 then
    enemy = newenemy(x, y, 80)
    enemy:multpower(1.25, 1.5)
  else
    enemy = newenemy(x, y, 96)
    enemy:multpower(1.5, 2)
  end
  add(enemies, enemy)
  add(stage, enemy)
end

function spawnflower()
  local padding = 30

  local flower = newflower(0, 0, flr(random(32, 36)))
  flower.pos.x = random(padding, stagewidth - padding)
  flower.pos.y = random(padding, stagewidth - padding)

  -- ensure the flower is not placed too closely to any other flower
  local trycount = 0
  while trycount < 5 and findclosest(flowers, flower.pos.x, flower.pos.y, function(obj, dist)
    return dist < flower.radius * 3
  end) != nil do
    flower.pos.x = random(padding, stagewidth - padding)
    flower.pos.y = random(padding, stagewidth - padding)
    trycount += 1
  end

  addflower(flower)

end

function addflower(flower)
  add(flowers, flower)
  add(anchors, flower)
  add(stage, flower)
end

function placeanchor(x, y)
  local closest = findclosest(anchors, x, y, function(obj, dist)
    return dist <= obj.radius
  end)
  if closest == nil then
    closest = newanchor(x, y)
    add(anchors, closest)
    add(stage, closest)
    sfx(1)
  end

  return closest
end

function removeanchor(x, y)
  local closest = findclosest(anchors, x, y, function(obj, dist)
    return dist <= obj.radius
  end)
  if closest != nil then
    if closest.removable then
      del(anchors, closest)
      del(stage, closest)
    end
    if closest == beehive and beehive.isfirst then
      beehive.isfirst = false
    end
    return closest
  end
  return nil
end

function findclosest(coll, x, y, cond)
  local closest = nil
  local closestdist = 32000
  for obj in all(coll) do
    local diff = vsub(obj.pos, newvector(x, y))
    local dist = diff:mag()
    if dist < closestdist and cond(obj, dist) then
      closest = obj
      closestdist = dist
    end
  end
  return closest
end

function getsprite(sprites, totaltime)
  local timeframe = time % totaltime
  local frametime = totaltime / count(sprites)

  return sprites[flr(timeframe / frametime) + 1] -- +1 because arrays start at 1 in lua
end

function chooserandom(coll)
  return coll[flr(random(1, count(coll) + 1))]
end

function random(min, max)
  return rnd(max - min) + min
end

function notoncamera(x, y, width, height)
  local x1 = cam.x
  local y1 = cam.y
  local x2 = cam.x + cam.width
  local y2 = cam.y + cam.height
  return (x + width/2) < x1 or (x - width/2) > x2 or (y + height/2) < y1 or (y - height/2) > y2
end

function getstringwidth(s)
  local len = #s
  return 4 * len - 1
end

function printcenter(s, y, color)
  local width = getstringwidth(s)
  print(s, cam.x + cam.width/2 - flr(width/2), y, color)
end

function drawindicator(target, top, bottom, left, right)
  local diff = vsub(target.pos, newvector(cam.x + cam.width/2, cam.y + cam.height/2))
  local sprite = 0
  local x = 0
  local y = 0
  if abs(diff.x) > abs(diff.y) then
    if diff.x <= 0 then
      sprite = left
      x = cam.x
    else
      sprite = right
      x = cam.x + cam.width - 3
    end
    y = min(max(target.pos.y, cam.y), cam.y + cam.height - 5)
  else
    if diff.y <= 0 then
      sprite = top
      y = cam.y
    else
      sprite = bottom
      y = cam.y + cam.height - 3
    end
    x = min(max(target.pos.x - 2, cam.x), cam.x + cam.width - 5)
  end

  spr(sprite, x, y)
end

-- ============================
-- classes
-- ============================
function newgameobj()
  local obj = {}
  obj.pos = newvector(0, 0)
  obj.vel = newvector(0, 0)
  obj.layer = 1

  function obj:dist(other)
    return vsub(self.pos, other.pos):mag()
  end

  return obj
end

function newcursor(x, y)
  local cursor = newanchor(x, y)
  cursor.speed = 1
  cursor.radius = 10
  cursor.layer = cursor_layer
  cursor.removable = false

  function cursor:update()
    self:superupdate()

    -- movement
    self.vel.x = 0
    self.vel.y = 0
    if btn(0) then self.vel.x = -self.speed end
    if btn(1) then self.vel.x = self.speed end
    if btn(2) then self.vel.y = -self.speed end
    if btn(3) then self.vel.y = self.speed end

    -- add anchor
    if btnp(4) then
      if count(self.bees) > 0 then
        local anchor = placeanchor(self.pos.x, self.pos.y)
        local bee = findclosest(self.bees, self.pos.x, self.pos.y, function(obj, dist) return true end)
        bee:setanchor(anchor)
        if count(anchor.bees) > 1 or not anchor.removable then sfx(2) end
      else
        sfx(0)
      end
    end

    -- remove anchor
    if btnp(5) then
      local anchor = removeanchor(self.pos.x, self.pos.y)
      if anchor != nil then
        if count(anchor.bees) > 0 then sfx(3) else sfx(0) end
        for bee in all(anchor.bees) do
          bee:setanchor(cursor)
        end

      else
        sfx(0)
      end
    end

    local newpos = vadd(self.pos, self.vel)
    if newpos.x < 0 or newpos.x > stagewidth then self.vel.x = 0 end
    if newpos.y < 0 or newpos.y > stageheight then self.vel.y = 0 end
  end

  function cursor:draw()
    spr(0, self.pos.x - 1, self.pos.y - 1)
  end

  return cursor
end

function newbeehive(x, y)
  local beehive = newanchor(x, y)
  beehive.layer = beehive_layer
  beehive.anim = {16, 17, 18}
  beehive.removable = false
  beehive.pollen = 0
  beehive.maxpollen = 10
  beehive.progressbar = newhealthbar(beehive, 9)
  beehive.progressbar.bgcolor = 4
  beehive.progressbar.fgcolor = 9
  beehive.progressbar.height = 1
  beehive.isfirst = true

  function beehive:update()
    self:superupdate()
  end

  function beehive:draw()
    spr(getsprite(self.anim, 72), self.pos.x - 4, self.pos.y)
    rectfill(self.pos.x - 1, self.pos.y + 6, self.pos.x, self.pos.y + 7, 0)

    -- draw progress bar for bee production
    if self.pollen > 0 then
      self.progressbar:draw(self.pollen, self.maxpollen)
    end

    -- draw pick-up hint if it's the first time the player is picking up bees
    if self.isfirst then
      print('btn2 to', self.pos.x - 13, self.pos.y + 9, 7)
      print('pick up', self.pos.x - 13, self.pos.y + 15, 7)
    end
  end

  function beehive:pollinate()
    self.pollen = min(self.pollen + 1, self.maxpollen)
    if self.pollen == self.maxpollen then
      local bx = random(self.pos.x - 3, self.pos.x + 3)
      local by = random(self.pos.y - 3, self.pos.y + 3)
      addbee(newbee(bx, by, self))
      self.pollen = 0
    end
  end

  return beehive
end

function newanchor(x, y)
  local anchor = newgameobj()
  anchor.pos.x = x
  anchor.pos.y = y
  anchor.radius = 10
  anchor.bees = {}
  anchor.layer = anchor_layer
  anchor.removable = true
  anchor.closestenemy = nil

  function anchor:update()
    self:superupdate()
  end

  function anchor:superupdate()
    self.closestenemy = findclosest(enemies, self.pos.x, self.pos.y, function(obj, dist)
      return obj.health > 0 and dist <= self.radius
    end)
  end

  function anchor:draw()
    circ(self.pos.x, self.pos.y, self.radius, 3)
  end

  return anchor
end

function newbee(x, y, anchor)
  local bee = newgameobj()
  bee.pos.x = x
  bee.pos.y = y
  bee.maxspeed = 2.5
  bee.vision = 5
  bee.targetvision = 10
  bee.minelevation = 1
  bee.maxelevation = 5
  bee.elevation = random(bee.minelevation, bee.maxelevation)
  bee.targetelevation = random(bee.minelevation, bee.maxelevation)
  bee.anchor = anchor
  bee.layer = bee_layer
  bee.attackspeed = 10
  bee.health = 3
  bee.closestbee = nil

  function bee:update()
    -- calculate the closest bee once for use by all future functions
    self:updateclosestbee()

    -- handle anchors and targets
    local targetanchor = self:targetanchor()
    local targetenemy = self:targetenemy()
    targetenemy:mult(2.5)

    -- implement the traditional swarming algorithm
    -- http://processingjs.org/learning/topic/flocking/
    local separation = self:separation()
    separation:mult(0.5)

    local alignment = self:alignment()
    alignment:mult(0.05)
    --
    local cohesion = self:cohesion()
    cohesion:mult(0.05)

    -- sum 'em all up
    self.vel:add(targetenemy)
    self.vel:add(targetanchor)
    self.vel:add(separation)
    self.vel:add(alignment)
    self.vel:add(cohesion)

    -- keep everything under a maximum speed
    local currspeed = self.vel:mag()
    if currspeed > self.maxspeed then
      local rads = atan2(self.vel.x, self.vel.y)
      self.vel.x = cos(rads) * self.maxspeed
      self.vel.y = sin(rads) * self.maxspeed
    end

    -- adjust elevation
    local ediff = self.targetelevation - self.elevation
    if abs(ediff) > 0.1 then
      self.elevation += ediff * 0.15
    else
      self.targetelevation = random(self.minelevation, self.maxelevation)
    end

    -- attack
    self:attack()
  end

  function bee:draw()
    -- draw shadow at actual position (so the shadow is stable on the ground), but offset it by a little so the yellow
    -- pixel doesn't seem so far from the actual programmatic position
    pset(self.pos.x, self.pos.y + self.minelevation, 3)

    -- draw the yellow bit where the bee is, taking elevation into account
    local color = 10
    if self.health == 2 then color = 9
    elseif self.health <= 1 then color = 8 end
    pset(self.pos.x, self.pos.y - self.elevation + self.minelevation, color)
  end

  function bee:sethealth(health)
    self.health = max(0, health)
    if health == 0 then
      del(self.anchor.bees, self)
      del(bees, self)
      del(stage, self)
    end
  end

  function bee:updateclosestbee()
    if self.closestbee == nil then
      self.closestbee = findclosest(self.anchor.bees, self.pos.x, self.pos.y, function(obj, dist)
        return obj != self and dist < self.vision
      end)
    end
    if self.closestbee != nil then
      -- cache calculation for other bee
      self.closestbee.closestbee = self
    end
  end

  function bee:targetenemy()
    local enemy = self.anchor.closestenemy

    if enemy != nil then
      local diff = vsub(enemy.pos, self.pos)
      local rads = atan2(diff.x, diff.y)

      local tvec = newvector(cos(rads), sin(rads))
      tvec:norm()
      return tvec
    else
      return newvector(0, 0)
    end
  end

  function bee:targetanchor()
    local diff = vsub(self.anchor.pos, self.pos)
    local rads = atan2(diff.x, diff.y)
    local tvec = newvector(cos(rads), sin(rads))

    local dist = diff:mag()
    -- keep bees from wandering
    if dist > 20 then
      self.pos.x = self.anchor.pos.x - (tvec.x * dist)
      self.pos.y = self.anchor.pos.y - (tvec.y * dist)
      self.vel.x = 0
      self.vel.y = 0
    end

    tvec:norm()

    -- make strength of pull strong the further away the bee is from the cursor
    return tvec
  end

  function bee:separation()
    if self.closestbee != nil then
      local diff = vsub(self.pos, self.closestbee.pos)
      diff:norm()
      return diff
    else
      return newvector(0, 0)
    end
  end

  function bee:alignment()
    if self.closestbee != nil then
      return vadd(self.vel, bee.vel):div(2)
    else
      return newvector(0, 0)
    end
  end

  function bee:cohesion(neighbors)
    if self.closestbee != nil then
      local avg = vadd(self.vel, bee.vel):div(2)
      local diff = vsub(self.vel, avg)
      local rads = atan2(diff.x, diff.y)
      local vec = newvector(cos(rads), sin(rads))
      vec:norm()
      return vec
    else
      return newvector(0, 0)
    end
  end

  function bee:setanchor(anchor)
    del(self.anchor.bees, self)
    add(anchor.bees, self)
    self.anchor = anchor
  end

  function bee:attack()
    local enemy = self.anchor.closestenemy

    if enemy != nil and time % self.attackspeed == 0 then
      enemy:sethealth(enemy.health - 1)
    end
  end

  return bee
end

function newenemy(x, y, sprite)
  local enemy = newgameobj()
  enemy.pos.x = x
  enemy.pos.y = y
  enemy.layer = enemy_layer
  enemy.walkanim = {sprite, sprite + 1}
  enemy.attackanim = {sprite + 2, sprite + 3}
  enemy.runanim = {sprite + 4, sprite + 5}
  enemy.maxhealth = 100
  enemy.health = enemy.maxhealth
  enemy.healthbar = newhealthbar(enemy, -9)
  enemy.radius = 5
  enemy.attackspeed = 30
  enemy.walkspeed = .25
  enemy.state = 0 -- 0 = normal, 1 = attacking, 2 = running

  enemy.healthbar.width = 7

  function enemy:update()
    if self.state != 2 then
      self.state = 0
      self:attackifpossible()

      -- if we didn't attack anything, then walk towards a flower
      if self.state == 0 then
        self:targetflower()
      end
    else
      -- run away!
      self.vel.x = 0
      self.vel.y = -1
    end


  end

  function enemy:draw()
    if self.state == 0 then
      spr(getsprite(self.walkanim, 16), self.pos.x - 4, self.pos.y - 7)
    elseif self.state == 1 then
      spr(getsprite(self.attackanim, 16), self.pos.x - 4, self.pos.y - 7)
    elseif self.state == 2 then
      spr(getsprite(self.runanim, 4), self.pos.x - 4, self.pos.y - 7)
    end

    -- make eyes and mouth black
    if self.state != 2 then
      pset(self.pos.x - 2, self.pos.y - 4, 0)
      pset(self.pos.x + 2, self.pos.y - 4, 0)
      pset(self.pos.x, self.pos.y - 3, 0)

      -- draw health bar
      if self.health < self.maxhealth then
        self.healthbar:draw(enemy.health, enemy.maxhealth)
      end
    end
  end

  function enemy:multpower(healthmult, walkmult)
    self.maxhealth = self.maxhealth * healthmult
    self.health = self.maxhealth
    self.walkspeed = self.walkspeed * walkmult
  end

  function enemy:attackifpossible()
    local attacked = false

    -- try to attack a bee first (optimization: only examine bees at the closest anchor)
    add(anchors, cursor)
    local anchor = findclosest(anchors, self.pos.x, self.pos.y, function(obj, dist)
      return dist < obj.radius
    end)
    if anchor != nil and count(anchor.bees) > 0 then
      attacked = self:attack(anchor.bees)
    elseif not attacked then
      self:attack(flowers)
    end
    del(anchors, cursor)
  end

  function enemy:attack(coll)
    local obj = findclosest(coll, self.pos.x, self.pos.y, function(obj, dist)
      return dist <= self.radius
    end)

    if obj != nil then
      if time % self.attackspeed == 0 then
        obj:sethealth(obj.health - 1)
      end
      self.vel.x = 0
      self.vel.y = 0
      self.state = 1

      -- sound
      if coll != flowers and time % 5 == 0 then
        sfx(chooserandom({4, 5, 6}))
      end
      return true
    end
    return false
  end

  function enemy:targetflower()
    local flower = findclosest(flowers, self.pos.x, self.pos.y, function(obj, dist) return true end)

    -- flower will be nil during final update() call before game over
    if flower != nil then
      local diff = vsub(flower.pos, self.pos)
      local rads = atan2(diff.x, diff.y)

      self.vel.x = cos(rads) * self.walkspeed
      self.vel.y = sin(rads) * self.walkspeed
    end
  end

  function enemy:sethealth(health)
    self.health = max(0, health)
    if self.health == 0 then
      self.state = 2
    end
  end

  return enemy
end

function newflower(x, y, sprite)
  local flower = newanchor(x, y)
  flower.sprite = sprite
  flower.removable = false
  flower.maxhealth = 20
  flower.health = flower.maxhealth
  flower.healthbar = newhealthbar(flower, 5)
  flower.healthbar.width = 7
  flower.healthbar.xoffset = 1
  flower.pollenanimation = {48, 49, 50}
  flower.pollencount = 0
  flower.pollenspeed = 30
  flower.isattackedtimer = 0

  function flower:update()
    self:superupdate()

    if count(self.bees) > 0 then
      self.pollencount += 1
      if self.pollencount > self.pollenspeed then
        beehive:pollinate()
        self.pollencount = 0
      end
    end

    if self.isattackedtimer > 0 then
      self.isattackedtimer -= 1
    end
  end

  function flower:draw()
    spr(self.sprite, self.pos.x - 2, self.pos.y - 2)
    circ(self.pos.x, self.pos.y, self.radius, 3)

    -- draw pollination if we have bees on us
    if count(self.bees) > 0 then
      spr(getsprite(self.pollenanimation, 30), self.pos.x - 3, self.pos.y)
    end

    -- draw the health bar
    if self.health < self.maxhealth then
      self.healthbar:draw(self.health, self.maxhealth)
    end

    -- draw appropriate off-screen indicator
    if notoncamera(self.pos.x, self.pos.y, 5, 7) then
      if self.isattackedtimer > 0 then
        -- being attacked
        drawindicator(self, 130, 131, 128, 129)
      elseif self.closestenemy != nil then
        -- bees attacking
        drawindicator(self, 146, 147, 144, 145)
      else
        -- normal state
        drawindicator(self, 162, 163, 160, 161)
      end
    end
  end

  function flower:sethealth(health)
    self.health = max(0, health)
    self.isattackedtimer = 30
    if self.health == 0 then
      del(flowers, self)
      del(anchors, self)
      del(stage, self)
      lives -= 1
      if lives <= 0 then
        screen = 2
      end
    end
  end

  return flower
end

function newbeecounter()
  local beecounter = newgameobj()
  beecounter.layer = hud_layer

  function beecounter:update()
  end

  function beecounter:draw()
    -- we have to get the cam position here because the camera is adjusted during the draw call
    local message = count(cursor.bees) .. '/' .. count(bees)
    print(message, cam.x + cam.width - getstringwidth(message) - 1, cam.y + 1, 7)
  end

  return beecounter
end

function newlifecounter()
  local lifecounter = newgameobj()
  lifecounter.layer = hud_layer

  function lifecounter:update()
  end

  function lifecounter:draw()
    local y = 7
    local x = cam.width - 4
    for i = lives, 1, -1 do
      spr(3, cam.x + x, cam.y + y)
      x -= 4
    end
  end

  return lifecounter

end

function newscore()
  local scorecounter = newgameobj()
  scorecounter.layer = hud_layer

  function scorecounter:update()
    if time % 30 == 0 and not beehive.isfirst then
      score += 1
    end
  end

  function scorecounter:draw()
    -- we have to get the cam position here because the camera is adjusted during the draw call
    printcenter(score .. '', cam.y + cam.height - 6, 7)
  end

  return scorecounter
end

function newhealthbar(target, yoffset)
  healthbar = {}
  healthbar.target = target
  healthbar.yoffset = yoffset
  healthbar.xoffset = 0
  healthbar.bgcolor = 8
  healthbar.fgcolor = 12
  healthbar.height = 1
  healthbar.width = 8

  function healthbar:update()
  end

  function healthbar:draw(current, total)
    local innerwidth = max((current / total) * self.width - 1, 0)

    local x1 = target.pos.x - (self.width / 2) + self.xoffset
    local y1 = target.pos.y + self.yoffset + (sgn(self.yoffset) * (1 -  self.height))
    local x2 = x1  + self.width - 1
    local y2 = target.pos.y + self.yoffset

    rectfill(x1, y1, x2, y2, self.bgcolor)
    if innerwidth > 0 then
      rectfill(x1, y1, x1 + innerwidth, y2, self.fgcolor)
    end
  end

  return healthbar
end

function newvector(x, y)
  local vec = {}
  vec.x = x
  vec.y = y

  function vec:add(v)
    self.x += v.x
    self.y += v.y
    return self
  end

  function vec:sub(v)
    self.x -= v.x
    self.y -= v.y
    return self
  end

  function vec:mult(s)
    self.x *= s
    self.y *= s
    return self
  end

  function vec:div(s)
    self.x /= s
    self.y /= s
    return self
  end

  function vec:mag()
    -- need to be careful not to overflow pico's 16-bit integers
    -- we basically convert to different "units" and then convert back
    local unit = 100
    local nx = self.x / unit
    local ny = self.y / unit
    local dist = sqrt(nx * nx + ny * ny)
    return dist * unit
  end

  function vec:norm()
    local mag = self:mag(vec)
    if mag != 0 then
      self.x = self.x / mag
      self.y = self.y / mag
    end
  end

  return vec
end

function vadd(v1, v2)
  return newvector(v1.x + v2.x, v1.y + v2.y)
end

function vsub(v1, v2)
  return newvector(v1.x - v2.x, v1.y - v2.y)
end

function vmult(v, s)
  return newvector(v.x * s, v.y * s)
end

function vdiv(v, s)
  return newvector(v.x / s, v.y / s)
end

__gfx__
07000000bbbbbbbbbbbbbbbb80800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77700000bbbbbbbbbbbbbbbb88800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000000bbbbbbbbb3bbbbbb08000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000bbbbbbbbb33bbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000bbbbbbbbbb3b3bbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000bbbbbbbbbb33bbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000bbbbbbbbbbb3bbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000bbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044000000440000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a9000000a90000009a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00444400004444000044440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
009aa900009aa900009a9a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04499440044944400444494000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0aaaa9a00aa9a9a00aa9a9a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44900444449004444440049440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a9a0099aaa900a9aaa900a9aa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
02220000e0e0e0000ccc000070707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
02e20000eeeee0000c7c000077777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
022200000eee00000ccc000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300000003000000030000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
03300000003300000330000000330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300000003000000030000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000f000f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000f000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00f0f00000000000f00000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000f00000f000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000f0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000f000f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
09000009090000090900000909000009900000909000009000000000000000000000000000000000000000000000000000000000000000000000000000000000
09900099099000990990009909900099990009909900099000000000000000000000000000000000000000000000000000000000000000000000000000000000
04999994049999940499999404999994999999909999999000000000000000000000000000000000000000000000000000000000000000000000000000000000
00099900000999000009990000099900099999000999990000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ff0ff000ff0ff000ff0ff000ff0ff00f999f000f999f0000000000000000000000000000000000000000000000000000000000000000000000000000000000
f9044400f904440000048409090444000044409f0044409f00000000000000000000000000000000000000000000000000000000000000000000000000000000
09499900094999000099999000999990009994900099949000000000000000000000000000000000000000000000000000000000000000000000000000000000
00090000000009000909090000090909009000000000900000000000000000000000000000000000000000000000000000000000000000000000000000000000
06000006060000060600000606000006600000606000006000000000000000000000000000000000000000000000000000000000000000000000000000000000
06600066066000660660006606600066660006606600066000000000000000000000000000000000000000000000000000000000000000000000000000000000
05666665056666650566666505666665666666606666666000000000000000000000000000000000000000000000000000000000000000000000000000000000
00066600000666000006660000066600066666000666660000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ff0ff000ff0ff000ff0ff000ff0ff00f666f000f666f0000000000000000000000000000000000000000000000000000000000000000000000000000000000
f6055500f605550000058506060444000055506f0055506f00000000000000000000000000000000000000000000000000000000000000000000000000000000
06566600065666000066666000666660006665600066656000000000000000000000000000000000000000000000000000000000000000000000000000000000
00060000000006000606060000060606006000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c00000c0c00000c0c00000c0c00000cc00000c0c00000c000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cc000cc0cc000cc0cc000cc0cc000cccc000cc0cc000cc000000000000000000000000000000000000000000000000000000000000000000000000000000000
0dcccccd0dcccccd0dcccccd0dcccccdccccccc0ccccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000
000ccc00000ccc00000ccc00000ccc000ccccc000ccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ff0ff000ff0ff000ff0ff000ff0ff00fcccf000fcccf0000000000000000000000000000000000000000000000000000000000000000000000000000000000
fc0ddd00fc0ddd00000d8d0c0c0ddd0000ddd0cf00ddd0cf00000000000000000000000000000000000000000000000000000000000000000000000000000000
0cdccc000cdccc0000ccccc000ccccc000cccdc000cccdc000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000000000c000c0c0c00000c0c0c00c000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00800000800000000080000088888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08800000880000000888000008880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88800000888000008888800000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08800000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00800000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00900000900000000090000099999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
09900000990000000999000009990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
99900000999000009999900000900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
09900000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00900000900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300000300000000030000033333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
03300000330000000333000003330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
33300000333000003333300000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
03300000330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
09999999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
99aaaaaaaaaa99000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaaa9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaaa9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaa99999aaa9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaa9900099999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaa9900000000000000000099999999999999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaa99999999999900099999aaaaa99aaaaaaaa9999999999000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaa99aa90009aa9aaa9aa99aaaaaaaa99aaa9aaa9900000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaaa9aa90009aa9aa999aa9aa9999aa9aaaaaaaaa900000000000000000000000000000000000000000000000000000000000000000000000000000
99aaaaaaaaaaa9aa90009aa9aa999aa9aa9999aa9aa9aaa9aa900000000000000000000000000000000000000000000000000000000000000000000000000000
099999999aaaa9aa90009aa9aaaaaaa9aaaaaaaa9aa99a99aa900000000000000000000000000000000000000000000000000000000000000000000000000000
0000000099aaa9aa90909aa9aaaaaaa9aaaaaaa99aa99999aa900000000000000000000000000000000000000000000000000000000000000000000000000000
9999900099aaa9aa99999aa9aa999aa9aa999aa99aa90909aa900000000000000000000000000000000000000000000000000000000000000000000000000000
9aaa99999aaaa9aa99a99aa9aa999aa9aa909aaa9aa90009aa900000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaaa9aa9aaa9aa9aa909aa9aa9099aa9aa90009aa900000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaaaaaaaaaa9aaaaaaaaa9aa909aa9aa9009aa9aa90009aa900000000000000000000000000000000000000000000000000000000000000000000000000000
99aaaaaaaaaa999aaa9aaa99aa909aa9aa9009aa9aa90009aa900000000000000000000000000000000000000000000000000000000000000000000000000000
09999999999990999999999999909999999009999999000999900000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000088888888
__gff__
0000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101010101010101010101010101010201010101010101010101010201010101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020101010101010101020101010101010101010201010101010101010101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010102010101020101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010102010101010101010101010201010101010101010101010101ffff0101010101010201ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0201010101010101010101010101020101010101010101010101010101010101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010102010101010101010101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010201010101010201010101010101010101010201ffff0102010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020101010101020101010101010101010101010101010102010101010101ffff0101010101010101ffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010201010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010102010101010101010101010101010101010101010201ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102010101010201010101010101020101010101010102010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010201010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101020101010201010101010201010102010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020101010101010101010101010101010101010101010101010101010201ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010201010101010101010201010101010201010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101020101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010201010101010201010101010102010101010101010201ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010102010101010101010101020101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010201010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101020101010101010101010201010101010101010101010101010101010102ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010201010101010101010201010101010201010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010201010101010101010201010101010101020101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101ffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
00020000010700107001070010700100007700010700107001070010700100001700075000c700065000f700055000b70009700045000c700035000c7000c700025000c700015000c7000c7000c7000c7000c700
000300000213002130021300130007130071300713004300107000f7000f7000f7001170015700197000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001104000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030000201102011020110000001b1201b1201b12000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000315000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000414000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000514000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 42424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

