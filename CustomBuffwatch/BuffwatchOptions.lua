-- Local vars and funcs
local addonName, BUFFWATCHADDON = ...;

BUFFWATCHADDON_G.TOOLTIP = { };
BUFFWATCHADDON_G.TOOLTIP.ALPHA = "Sets the transparency of the Buffwatch window";
BUFFWATCHADDON_G.TOOLTIP.ANCHORPOINT = "Determines which direction the window expands when resizing";
BUFFWATCHADDON_G.TOOLTIP.COOLDOWNTEXTSCALE = "Sets the scale of Blizzard cooldown text, if enabled";
BUFFWATCHADDON_G.TOOLTIP.HIDECOOLDOWNTEXT = "Hide Blizzard cooldown text overlays";
BUFFWATCHADDON_G.TOOLTIP.MODE = "Selects which players to show";
BUFFWATCHADDON_G.TOOLTIP.SCALE = "Sets the scale of the Buffwatch window";
BUFFWATCHADDON_G.TOOLTIP.SHOWALLFORPLAYER = "Always show all buffs for this player";
BUFFWATCHADDON_G.TOOLTIP.SHOWCASTABLEBUFFS = "Only show buffs you can cast on other players";
BUFFWATCHADDON_G.TOOLTIP.SHOWONLYMINE = "Only show buffs you have cast";
BUFFWATCHADDON_G.TOOLTIP.SHOWPETS = "Show pets in the player list";
BUFFWATCHADDON_G.TOOLTIP.PARTYSECONDROW = "Show yourself alone on the top row, and party members side by side on the row below";
BUFFWATCHADDON_G.TOOLTIP.KEEPCENTRED = "Keep the window centred when it grows or shrinks, instead of expanding to the right";
BUFFWATCHADDON_G.TOOLTIP.SHOWSPIRALS = "Enable cooldown spirals on buff buttons";
BUFFWATCHADDON_G.TOOLTIP.SORTORDER = "Specifies the sort order for the player list in the Buffwatch Window";
BUFFWATCHADDON_G.TOOLTIP.VISIBLE = "Show or hide the Buffwatch window";

-- Temp global & player options
local BuffwatchTempConfig = {};
local BuffwatchTempPlayerConfig = {};

function BUFFWATCHADDON_G.HelpFrame_OnLoad(self)

    local optionsFrame = _G["Buffwatch_Options"];

    Buffwatch_Options_Title:SetText(BUFFWATCHADDON.NAME);

    optionsFrame.name = BUFFWATCHADDON.NAME;
    optionsFrame.default = BUFFWATCHADDON.Options_SetDefaults;
    optionsFrame.refresh = BUFFWATCHADDON.Options_Init;
    optionsFrame.cancel = BUFFWATCHADDON.Options_CancelButton;

    Buffwatch_HelpFrameText_Title:SetText("  - |cff5555ffBuffwatch Usage|cffffffff - v|cffff5555" .. BUFFWATCHADDON.VERSION .. " |cffffffff- ");

    Buffwatch_HelpFrameText_Body:SetText([[
  1) Make sure the buffs you want to monitor are on the relevant
       players

  2) Tick the checkbox next to each player which locks those buffs
       to the player (alternatively tick the checkbox at the top to lock
       them all)

  3) Remove monitoring of the buffs you are not interested in, using
       the following methods :

     * |cffff5555Right Click|cffffffff to remove the selected buff (locked or not)

     * |cffff5555Alt|cffffffff-|cffff5555Left Click|cffffffff to remove all buffs but the selected one

  4) Buffs that have expired will turn red, and clicking on them will
       recast the buff on the player (if you have the spell)

  5) A player's row locks itself when they die, so their buffs stay
       tracked and turn red once they're back


  Other features :

     - Left click a player name to target that player

     - Right click a player name to assist that player (target their target)


  Buffwatch commands (/buffwatch):

     /buffwatch toggle - Toggle the Buffwatch window on or off

     /buffwatch options - Toggle the options window on or off

     /buffwatch reset - Reset the window position

     /buffwatch always [buff name] - List, add or remove buffs that are
       shown even when a filter would hide them (Well Fed by default)

     /buffwatch help - Show this help page


  Right click the Buffwatch header for more options
]] );

    self.name = BUFFWATCHADDON.HELPFRAMENAME;
    self.parent = optionsFrame;

    -- Keep the categories' own IDs: Settings.OpenToCategory needs the numeric
    -- ID from GetID(), so overwriting it with a name stops the panel opening.
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name);
    Settings.RegisterAddOnCategory(category);
    BUFFWATCHADDON.OptionsCategory = category;

    BUFFWATCHADDON.HelpCategory = Settings.RegisterCanvasLayoutSubcategory(category, self, self.name);

    Buffwatch_HelpFrameText_Title:ClearAllPoints();
    Buffwatch_HelpFrameText_Title:SetPoint("TOPLEFT", 10, -4);
    Buffwatch_HelpFrameText_Title:SetPoint("BOTTOMRIGHT", -55, 25);

    Buffwatch_HelpFrameText_Body:ClearAllPoints();
    Buffwatch_HelpFrameText_Body:SetPoint("TOPLEFT", 10, -30);
    Buffwatch_HelpFrameText_Body:SetPoint("BOTTOMRIGHT", -55, 5);

end

function BUFFWATCHADDON.Options_Init()

    BuffwatchTempConfig = CopyTable(BuffwatchConfig);
    BuffwatchTempPlayerConfig = CopyTable(BuffwatchPlayerConfig);

    UIDropDownMenu_SetSelectedValue(Buffwatch_Options_Mode, BuffwatchPlayerConfig.Mode);
    UIDropDownMenu_SetText(Buffwatch_Options_Mode, BuffwatchPlayerConfig.Mode);

    UIDropDownMenu_SetSelectedValue(Buffwatch_Options_SortOrder, BuffwatchPlayerConfig.SortOrder);
    UIDropDownMenu_SetText(Buffwatch_Options_SortOrder, BuffwatchPlayerConfig.SortOrder);

    UIDropDownMenu_SetSelectedValue(Buffwatch_Options_AnchorPoint, BuffwatchPlayerConfig.AnchorPoint);
    UIDropDownMenu_SetText(Buffwatch_Options_AnchorPoint, BuffwatchPlayerConfig.AnchorPoint);

    Buffwatch_Options_Visible:SetChecked(BuffwatchPlayerConfig.Visible);

    Buffwatch_Options_ShowPets:SetChecked(BuffwatchPlayerConfig.ShowPets);

    Buffwatch_Options_PartySecondRow:SetChecked(BuffwatchPlayerConfig.PartySecondRow);
    Buffwatch_Options_KeepCentred:SetChecked(BuffwatchPlayerConfig.KeepCentred);

    Buffwatch_Options_ShowOnlyMine:SetChecked(BuffwatchPlayerConfig.ShowOnlyMine);
    BUFFWATCHADDON_G.Options_ShowOnlyMine_OnClick(Buffwatch_Options_ShowOnlyMine, true);

    Buffwatch_Options_ShowOnlyCastableBuffs:SetChecked(BuffwatchPlayerConfig.ShowCastableBuffs);
    BUFFWATCHADDON_G.Options_ShowOnlyCastableBuffs_OnClick(Buffwatch_Options_ShowOnlyCastableBuffs, true);

    Buffwatch_Options_ShowAllForPlayer:SetChecked(BuffwatchPlayerConfig.ShowAllForPlayer);

    Buffwatch_Options_ShowSpirals:SetChecked(BuffwatchConfig.Spirals);
    BUFFWATCHADDON_G.Options_ShowSpirals_OnClick(Buffwatch_Options_ShowSpirals, true);

    Buffwatch_Options_HideCooldownText:SetChecked(BuffwatchConfig.HideCooldownText);

    Buffwatch_Options_Alpha:SetValue(BuffwatchConfig.Alpha);

    Buffwatch_Options_Scale:SetValue(BuffwatchPlayerConfig.Scale);

    Buffwatch_Options_CooldownTextScale:SetValue(BuffwatchConfig.CooldownTextScale);

    if (BUFFWATCHADDON.framePositioned == true) then
        BUFFWATCHADDON.GetAllBuffs();
    end
end

function BUFFWATCHADDON.Options_Mode_OnClick(self)
    local i = self:GetID();
    UIDropDownMenu_SetSelectedID(Buffwatch_Options_Mode, i);
    BuffwatchPlayerConfig.Mode = BUFFWATCHADDON.MODE_DROPDOWN_LIST[i];
    BUFFWATCHADDON.Set_UNIT_IDs();
    BUFFWATCHADDON.ResizeWindow();
end

function BUFFWATCHADDON.Options_Mode_Initialize()
    local info;
    for i = 1, #BUFFWATCHADDON.MODE_DROPDOWN_LIST do
        info = {
            text = BUFFWATCHADDON.MODE_DROPDOWN_LIST[i],
            func = BUFFWATCHADDON.Options_Mode_OnClick
        };
        UIDropDownMenu_AddButton(info);
    end
end

function BUFFWATCHADDON_G.Options_Mode_OnLoad(self)
    UIDropDownMenu_Initialize(self, BUFFWATCHADDON.Options_Mode_Initialize);
    UIDropDownMenu_SetWidth(self, 90);
end

function BUFFWATCHADDON.Options_SortOrder_OnClick(self)
    local i = self:GetID();
    UIDropDownMenu_SetSelectedID(Buffwatch_Options_SortOrder, i);
    BuffwatchPlayerConfig.SortOrder = BUFFWATCHADDON.SORTORDER_DROPDOWN_LIST[i];
    BUFFWATCHADDON.PositionAllPlayerFrames();
end

function BUFFWATCHADDON.Options_SortOrder_Initialize()
    local info;
    for i = 1, #BUFFWATCHADDON.SORTORDER_DROPDOWN_LIST do
        info = {
            text = BUFFWATCHADDON.SORTORDER_DROPDOWN_LIST[i],
            func = BUFFWATCHADDON.Options_SortOrder_OnClick
        };
        UIDropDownMenu_AddButton(info);
    end
end

function BUFFWATCHADDON_G.Options_SortOrder_OnLoad(self)
    UIDropDownMenu_Initialize(self, BUFFWATCHADDON.Options_SortOrder_Initialize);
    UIDropDownMenu_SetWidth(self, 90);
end

function BUFFWATCHADDON.Options_AnchorPoint_OnClick(self)
    local i = self:GetID();
    UIDropDownMenu_SetSelectedID(Buffwatch_Options_AnchorPoint, i);
    BuffwatchPlayerConfig.AnchorPoint = BUFFWATCHADDON.ANCHORPOINT_DROPDOWN_LIST[i];
    BUFFWATCHADDON.GetPoint(BuffwatchFrame, BUFFWATCHADDON.ANCHORPOINT_DROPDOWN_MAP[BuffwatchPlayerConfig.AnchorPoint]);
end

function BUFFWATCHADDON.Options_AnchorPoint_Initialize()
    local info;
    for i = 1, #BUFFWATCHADDON.ANCHORPOINT_DROPDOWN_LIST do
        info = {
            text = BUFFWATCHADDON.ANCHORPOINT_DROPDOWN_LIST[i],
            func = BUFFWATCHADDON.Options_AnchorPoint_OnClick
        };
        UIDropDownMenu_AddButton(info);
    end
end

function BUFFWATCHADDON_G.Options_AnchorPoint_OnLoad(self)
    UIDropDownMenu_Initialize(self, BUFFWATCHADDON.Options_AnchorPoint_Initialize);
    UIDropDownMenu_SetWidth(self, 100);
end

function BUFFWATCHADDON_G.Options_ShowPets_OnClick(self)
    if (self:GetChecked()) then
        BuffwatchPlayerConfig.ShowPets = true;
    else
        BuffwatchPlayerConfig.ShowPets = false;
    end
    BUFFWATCHADDON.Set_UNIT_IDs(true);
    BUFFWATCHADDON.ResizeWindow();
end

function BUFFWATCHADDON_G.Options_PartySecondRow_OnClick(self)
    BuffwatchPlayerConfig.PartySecondRow = self:GetChecked() and true or false;
    BUFFWATCHADDON.ResizeWindow();
end

function BUFFWATCHADDON_G.Options_KeepCentred_OnClick(self)
    BuffwatchPlayerConfig.KeepCentred = self:GetChecked() and true or false;
    BUFFWATCHADDON.ResizeWindow();
end

function BUFFWATCHADDON_G.Options_ShowOnlyMine_OnClick(self, suppressRefresh)
    if (self:GetChecked()) then
        BuffwatchPlayerConfig.ShowOnlyMine = true;
        BUFFWATCHADDON_G.Options_EnableCheckbox(Buffwatch_Options_ShowAllForPlayer);
    else
        BuffwatchPlayerConfig.ShowOnlyMine = false;
        if BuffwatchPlayerConfig.ShowCastableBuffs == false then
          BUFFWATCHADDON_G.Options_DisableCheckbox(Buffwatch_Options_ShowAllForPlayer);
        end
    end

    if (suppressRefresh ~= true) then
        BUFFWATCHADDON.GetAllBuffs();
    end
end

function BUFFWATCHADDON_G.Options_ShowOnlyCastableBuffs_OnClick(self, suppressRefresh)
    if (self:GetChecked()) then
        BuffwatchPlayerConfig.ShowCastableBuffs = true;
        BUFFWATCHADDON_G.Options_EnableCheckbox(Buffwatch_Options_ShowAllForPlayer);
    else
        BuffwatchPlayerConfig.ShowCastableBuffs = false;
        if BuffwatchPlayerConfig.ShowOnlyMine == false then
          BUFFWATCHADDON_G.Options_DisableCheckbox(Buffwatch_Options_ShowAllForPlayer);
        end
    end

    if (suppressRefresh ~= true) then
        BUFFWATCHADDON.GetAllBuffs();
    end

end

function BUFFWATCHADDON_G.Options_ShowAllForPlayer_OnClick(self)
    if (self:GetChecked()) then
        BuffwatchPlayerConfig.ShowAllForPlayer = true;
    else
        BuffwatchPlayerConfig.ShowAllForPlayer = false;
    end

    BUFFWATCHADDON.GetAllBuffs();

end

function BUFFWATCHADDON_G.Options_ShowSpirals_OnClick(self, suppressRefresh)
    if (self:GetChecked()) then
        BuffwatchConfig.Spirals = true;
        BUFFWATCHADDON_G.Options_EnableCheckbox(Buffwatch_Options_HideCooldownText);
    else
        BuffwatchConfig.Spirals = false;
        BUFFWATCHADDON_G.Options_DisableCheckbox(Buffwatch_Options_HideCooldownText);
    end

    if (suppressRefresh ~= true) then
        BUFFWATCHADDON.GetAllBuffs();
    end

end

function BUFFWATCHADDON_G.Options_HideCooldownText_OnClick(self)
    if (self:GetChecked()) then
        BuffwatchConfig.HideCooldownText = true;
    else
        BuffwatchConfig.HideCooldownText = false;
    end

    BUFFWATCHADDON.GetAllBuffs();

end

function BUFFWATCHADDON.Options_SetDefaults()
    BuffwatchConfig = CopyTable(BUFFWATCHADDON.DEFAULTS);
    BuffwatchPlayerConfig = CopyTable(BUFFWATCHADDON.PLAYER_DEFAULTS);
end

function BUFFWATCHADDON.Options_CancelButton()
    BuffwatchConfig = CopyTable(BuffwatchTempConfig);
    BuffwatchPlayerConfig = CopyTable(BuffwatchTempPlayerConfig);
    BUFFWATCHADDON.Options_Init();
    BUFFWATCHADDON.GetAllBuffs();
end

function BUFFWATCHADDON_G.Options_EnableCheckbox(checkbox)
    checkbox:Enable();
    _G[checkbox:GetName().."Text"]:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
end

function BUFFWATCHADDON_G.Options_DisableCheckbox(checkbox)
    checkbox:Disable();
    _G[checkbox:GetName().."Text"]:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b);
end