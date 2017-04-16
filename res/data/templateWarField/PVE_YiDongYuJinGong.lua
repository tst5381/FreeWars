return {
  warFieldName = "教程-移动与进攻",
  authorName   = "RushFTK",
  playersCount = 2,

  width = 12,
  height = 9,

  advancedSettings = {
    attackModifier            = 0,     -- 全局攻击力加成（百分比）：0=无加成（默认），-30=原作沙尘暴效果。可用范围：-100 ~ 无穷大
    energyGainModifier        = 100,   -- 全局能量获取速度倍率（百分比）：100=默认速率（默认），0=无法获得能量，200=两倍获取速度。可用范围：0 ~ 无穷大
    incomeModifier            = 100,   -- 全局收入倍率（百分比）：100=1000收入（默认），0=无收入，200=两倍（即2000）收入。可用范围：0 ~ 无穷大
    isActiveSkillEnabled      = true,  -- 是否启用主动技（布尔值）：true=是（默认），false=否。
    isFogOfWarByDefault       = false, -- 是否雾战（布尔值）：true=是，false=否（默认）。
    isPassiveSkillEnabled     = true,  -- 是否启用日常技（布尔值）：true=是（默认），false=否。
    isSkillDeclarationEnabled = true,  -- 是否启用主动技宣言（布尔值）：true=是（默认），false=否。
    playerIndex               = 1,     -- 玩家行动顺序（正整数）：1=红方（默认），2=蓝，3=黄，4=黑。可用范围：1 ~ 地图玩家总数
    moveRangeModifier         = 0,     -- 全局部队移动力加成（整数）：0=无加成（默认），-1=全部减一，1=全部+1。可用范围：任意整数（无论如何，部队最低移动力为1）
    startingEnergy            = 0,     -- 全局初始能量值（整数）：0=0（默认）。可用范围：0 ~ 无穷大
    startingFund              = 0,     -- 全局初始资金（整数）：0=0（默认）。可用范围：0 ~ 无穷大
    visionModifier            = 0,     -- 全局建筑及部队视野加成（整数）：0=无加成（默认），-1=全部减一，1=全部+1。中立建筑（火焰）不受影响。可用范围：任意整数（无论如何，建筑和部队最低视野为1）

    targetTurnsCount          = 5,     -- 速度100分目标天数
  },

  layers = {
    {
      type = "tilelayer",
      name = "tileBase",
      x = 0,
      y = 0,
      width = 12,
      height = 9,
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      properties = {},
      encoding = "lua",
      data = {
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        56, 1, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        20, 56, 14, 9, 1, 1, 1, 1, 1, 8, 1, 1,
        18, 34, 1, 1, 1, 1, 1, 1, 1, 6, 1, 1,
        19, 47, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        35, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        48, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
      }
    },
    {
      type = "tilelayer",
      name = "tileObject",
      x = 0,
      y = 0,
      width = 12,
      height = 9,
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      properties = {},
      encoding = "lua",
      data = {
        112, 117, 124, 123, 0, 0, 0, 124, 124, 125, 123, 124,
        126, 125, 0, 0, 0, 124, 0, 103, 0, 124, 124, 125,
        0, 124, 0, 0, 126, 123, 101, 106, 124, 124, 123, 124,
        0, 0, 0, 0, 0, 102, 124, 0, 0, 0, 124, 124,
        130, 0, 148, 124, 103, 106, 0, 124, 0, 0, 127, 124,
        0, 0, 147, 0, 102, 124, 123, 124, 0, 0, 124, 123,
        0, 0, 0, 103, 106, 124, 0, 0, 125, 0, 124, 103,
        0, 123, 0, 126, 124, 0, 124, 0, 124, 124, 123, 102,
        0, 0, 0, 124, 124, 147, 103, 104, 0, 124, 103, 106
      }
    },
    {
      type = "tilelayer",
      name = "unit",
      x = 0,
      y = 0,
      width = 12,
      height = 9,
      visible = true,
      opacity = 1,
      offsetx = 0,
      offsety = 0,
      properties = {},
      encoding = "lua",
      data = {
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 246, 0, 235, 247, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 231, 0, 0, 0,
        0, 0, 0, 0, 210, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 234, 0, 0, 0, 0, 235, 0, 0,
        0, 0, 274, 0, 0, 238, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 279, 0, 0, 0, 278
      }
    }
  }
}
