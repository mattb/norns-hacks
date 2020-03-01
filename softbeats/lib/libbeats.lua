-- TODO:
--
-- highpass filter - requires intelligently switching the wet/dry mix of HP and LP based on which one is in use, or having a priority override
-- grids UI

local Beets = {}
Beets.__index = Beets

function Beets.new(softcut_voice_id)
  local i = {
    id=softcut_voice_id,
    frames = 0,
    duration = 0,
    rate = 0,
    index = 0,
    played_index = 0,
    message = "",
    status = "",
    beatstep = 0,

    break_index_probability = 0,
    stutter_probability = 0,
    reverse_probability = 0,
    jump_probability = 0,
    jump_back_probability = 0,
    beat_start = 0,
    beat_end = 7,
    beat_count = 8,

    muted = false,
    initial_bpm = 0,
    current_bpm = 0,
    kickbeats = {},
    break_index = 1,
    break_offset = 5,
    break_count = 0
  }

  setmetatable(i, Beets)

  return i
end

function Beets:advance_step(in_beatstep, in_bpm)
  self.message = ""
  self.status = ""
  self.beatstep = in_beatstep
  self.current_bpm = in_bpm

  self.played_index = self.index
  self:play_slice(self.index)

  self:calculate_next_slice()
end

function Beets:instant_mute(in_muted)
  self:mute(in_muted)
  if self.muted then
    softcut.level(self.id,0)
  else
    softcut.level(self.id,1)
  end
end

function Beets:mute(in_muted)
  if in_muted then
    self.muted = true
  else
    self.muted = false
  end
end

function Beets:toggle_mute()
  self:mute(not self.muted)
end

function Beets:play_slice(slice_index) 
  crow.output[1]()
  if self.beatstep == 0 then
    crow.output[2]()
  end

  if(math.random(100) < self.stutter_probability) then
    self.message = self.message .. "STUTTER "
    local stutter_amount = math.random(4)
    softcut.loop_start(self.id, self.break_index * self.break_offset + (slice_index * (self.duration / self.beat_count)))
    softcut.loop_end(self.id, self.break_index * self.break_offset + (slice_index * (self.duration / self.beat_count) + (self.duration / (64.0 / stutter_amount))))
  else
    softcut.loop_start(self.id, self.break_index * self.break_offset)
    softcut.loop_end(self.id, self.break_index * self.break_offset + self.duration)
  end

  local current_rate = self.rate * (self.current_bpm / self.initial_bpm)
  if(math.random(100) < self.reverse_probability) then
    self.message = self.message .. "REVERSE "
    softcut.rate(self.id, 0-current_rate)
  else
    softcut.rate(self.id, current_rate)
  end

  if self.muted then
    softcut.level(self.id,0)
  else
    softcut.level(self.id,1)
  end

  local played_break_index
  if(math.random(100) < self.break_index_probability) then
    played_break_index = math.random(8) - 1
    self.message = self.message .. "BREAK "
  else
    played_break_index = self.break_index
  end
  softcut.position(self.id, played_break_index * self.break_offset + (slice_index * (self.duration / self.beat_count)))
  if self.muted then
    self.status = self.status .. "MUTED "
  end
  self.status = self.status .. "Sample: " .. played_break_index

  if self.kickbeats[played_break_index][slice_index] == 1 then
    crow.output[3]()
    self.message = self.message .. "KICK "
  end
end

function Beets:calculate_next_slice() 
  local new_index = self.index + 1
  if new_index > self.beat_end then
    -- self.message = self.message .. "LOOP "
    new_index = self.beat_start
  end

  if(math.random(100) < self.jump_probability) then
    self.message = self.message .. "> "
    new_index = (new_index + 1) % self.beat_count
  end

  if(math.random(100) < self.jump_back_probability) then
    self.message = self.message .. "< "
    new_index = (new_index - 1) % self.beat_count
  end

  if(self.beatstep == self.beat_count - 1) then
    -- message = message .. "RESET "
    new_index = self.beat_start
  end
  self.index = new_index
end

function Beets:init(breaks, in_bpm)
  self.kickbeats = {}

  self.initial_bpm = in_bpm
  local first_file = breaks[1].file
  local ch, samples, samplerate = audio.file_info(first_file) -- take all the settings from the first file for now
  self.frames = samples
  self.rate = samplerate / 48000.0 -- compensate for files that aren't 48Khz
  self.duration = samples / 48000.0
  print("Frames: " .. self.frames .. " Rate: " .. self.rate .. " Duration: " .. self.duration)

  for i, brk in ipairs(breaks) do
    softcut.buffer_read_mono(brk.file, 0, i * self.break_offset, -1, 1, 1)
    self.kickbeats[i] = {}
    for _, beat in ipairs(brk.kicks) do
      self.kickbeats[i][beat] = 1
    end
    self.break_count = i
  end
  
  softcut.enable(self.id,1)
  softcut.buffer(self.id,1)
  softcut.level(self.id,1)
  softcut.level_slew_time(self.id, 0.2)
  softcut.loop(self.id,1)
  softcut.loop_start(self.id, self.break_index * self.break_offset)
  softcut.loop_end(self.id, self.break_index * self.break_offset + self.duration)
  softcut.position(self.id, self.break_index * self.break_offset)
  softcut.rate(self.id,self.rate)
  softcut.play(self.id,1)
  softcut.fade_time(self.id, 0.010)

  softcut.post_filter_dry(self.id,0.0)
  softcut.post_filter_lp(self.id,1.0)
  softcut.post_filter_rq(self.id,0.3)
  softcut.post_filter_fc(self.id,44100)

  crow.output[1].action = "pulse(0.001, 5, 1)"
  crow.output[2].action = "pulse(0.001, 5, 1)"
  crow.output[3].action = "pulse(0.001, 5, 1)"
end

function Beets:add_params()
  local ControlSpec = require "controlspec"
  local Formatters = require "formatters"

  local specs = {}
  specs.FILTER_FREQ = ControlSpec.new(20, 20000, "exp", 0, 20000, "Hz")
  specs.FILTER_RESONANCE = ControlSpec.new(0.05, 1, "lin", 0, 0.25, "")
  specs.PERCENTAGE = ControlSpec.new(0, 1, "lin", 0.01, 0, "%")
  specs.BEAT_START = ControlSpec.new(0, self.beat_count - 1, "lin", 1, 0, "")
  specs.BEAT_END = ControlSpec.new(0, self.beat_count - 1, "lin", 1, self.beat_count - 1, "")

  params:add{type = "control", 
    id = "break_index",
    name="Sample",
    controlspec = ControlSpec.new(1, self.break_count, "lin", 1, 1, ""),
    action = function(value)
      self.break_index = value
    end}

  params:add{type = "control", 
    id = "jump_back_probability",
    name="Jump Back Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.jump_back_probability = value * 100
    end}

  params:add{type = "control", 
    id = "jump_probability",
    name="Jump Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.jump_probability = value * 100
    end}

  params:add{type = "control", 
    id = "reverse_probability",
    name="Reverse Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.reverse_probability = value * 100
    end}

  params:add{type = "control", 
    id = "stutter_probability",
    name="Stutter Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.stutter_probability = value * 100
    end}

  params:add{type = "control", 
    id = "break_index_probability",
    name="Break Index Probability",
    controlspec = specs.PERCENTAGE,
    formatter = Formatters.percentage,
    action = function(value)
      self.break_index_probability = value * 100
    end}

  params:add{type = "control", 
    id = "filter_frequency",
    name="Filter Cutoff",
    controlspec = specs.FILTER_FREQ,
    formatter = Formatters.format_freq,
    action = function(value)
      softcut.post_filter_fc(self.id, value) 
    end}

  params:add{type = "control", 
    id = "filter_reso",
    name="Filter Resonance",
    controlspec = specs.FILTER_RESONANCE,
    action = function(value)
      softcut.post_filter_rq(self.id, value)
    end}

  params:add{type = "control", 
    id = "beat_start",
    name = "Beat Start",
    controlspec = specs.BEAT_START,
    action = function(value)
      self.beat_start = value
    end}

  params:add{type = "control", 
    id = "beat_end",
    name = "Beat End",
    controlspec = specs.BEAT_END,
    action = function(value)
      self.beat_end = value
    end}
end

function Beets:drawUI()
  local horiz_spacing = 4
  local left_margin = 10
  screen.clear()
  screen.level(15)
  for i = 0,7 do 
    screen.move(left_margin + horiz_spacing * i, 17)
    screen.text("-")
    screen.move(left_margin + horiz_spacing * i, 23)
    screen.text("-")
    if i == self.beat_start or i == self.beat_end then 
      screen.move(left_margin + horiz_spacing * i, 26)
      screen.text("^")
    end
  end
  screen.move(left_margin + 1 + horiz_spacing * self.beatstep, 20)
  screen.text("|")
  screen.move(left_margin + horiz_spacing * self.played_index, 20)
  screen.text("-")
  screen.move(left_margin, 40)
  screen.text(self.message)
  screen.move(left_margin, 50)
  screen.text(self.status)
  screen.update()
end

return Beets
