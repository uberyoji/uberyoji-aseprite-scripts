----------------------------------------------------------------------
-- NES toolbox by uberyoji
--
-- Implements a couple of algorithms to be applied to NES char data.
-- - Analyze will select which 16x16 tiles have more than 4 colors/no colors matching any 4 color palettes
-- - Remap will make sure 16x16 tiles are using the same 4 colors palette entries
----------------------------------------------------------------------
if app.apiVersion < 1 then
    return app.alert("This script requires Aseprite v1.2.10-beta3")
end

local dlg = Dialog { title = "NES Toolbox" }

local function vprint(lvl, str)
    if dlg.data.verbose_mode and lvl <= dlg.data.verbose_level then print(str) end
end

local function hasColor(color,pal)
    for i=0, 3 do
        if pal[i]==color then
            return true
        end
    end
    return false
end

local function getColorIndex( color, pal )
    for i=0, 3 do
        if pal[i]==color then
            return i
        end
    end
    return app.alert{ title="Error", text="Oups. Cannot find color in palette.", buttons="OK"}
end    

local function paltostr( pal )
    return string.format("[ #%02x%02x%02x, #%02x%02x%02x, #%02x%02x%02x, #%02x%02x%02x ]", pal[0].red, pal[0].green,pal[0].blue, pal[1].red, pal[1].green,pal[1].blue, pal[2].red, pal[2].green,pal[2].blue, pal[3].red, pal[3].green,pal[3].blue)
end

local function getBestPal( acounts )
    for i=0, 3 do
        if acounts[i]==256 then
            return i
        end        
    end
    return -1
end

local function buildPals(pal)
    local pals = {}
    for i = 0, 3 do
        pals[i] = {}
    end
    for i = 0, 3 do                    
        for j = 0, 3 do
            pals[i][j] = pal:getColor(i * 4 + j)                        
        end
        vprint( 1, string.format("Palette %d: %s", i, paltostr(pals[i]) ) )
    end
    return pals
end

local function getImg(cel)
    if not cel then
        app.alert{ title="Error", text="There is no active image", buttons="OK"}
        return nil
    end
    -- The best way to modify a cel image is to clone it (the new cloned
    -- image will be an independent image, without undo information).
    -- Then we can change the cel image generating only one undoable
    -- action.
    local img = cel.image:clone()

    if img.width % 16 ~= 0 then
        app.alert{ title="Error", text="Image width is not a multiple of 16.", buttons="OK"}
        return nil
    end
    if img.height % 16 ~= 0 then
        app.alert{ title="Error", text="Image height is not a multiple of 16.", buttons="OK"}
        return nil
    end

     -- RGB mode is not supported
     if img.colorMode == ColorMode.RGB then
        app.alert{ title="Error", text="RGB image is not supported.", buttons="OK"}
        -- GRAY mode is not supported
    elseif img.colorMode == ColorMode.GRAY then
        app.alert{ title="Error", text="Grey scale image is not supported", buttons="OK"}
        -- For INDEXED mode we first count
        -- pixels with a ranom index that is not transparent too
    elseif img.colorMode == ColorMode.INDEXED then
        local n = #app.activeSprite.palettes[1]
        if n < 15 then -- works only on the first 16 colors  
            app.alert{ title="Error", text= "Palette need at least 16 colors.", buttons="OK"}
        else
            return img
        end
    end
    return nil
end

local function getTileBestPal( tx, ty, img, pal, apals )
    local tsy = ty*16
    local tsx = tx*16
    local counts = {}
    for i=0,3 do counts[i] = 0 end

    local col
    local idx

    -- try to find the best palette by counting how many index hits are found per palettes
    for y=tsy, tsy+15 do
        for x=tsx, tsx+15 do
            idx = img:getPixel(x,y)
            col = pal:getColor(idx)

            for p=0, 3 do
                if hasColor(col,apals[p]) then
                    counts[p] = counts[p] + 1
                end
            end
            vprint( 3, string.format("idx %d => #%02x%02x%02x", idx, col.red, col.green,col.blue) )
        end
    end

    vprint( 2, string.format( "Counts: %d, %d, %d, %d", counts[0],counts[1],counts[2],counts[3] ))
    return getBestPal(counts)
end

dlg:separator{ id="analyzing section", text="Analyze Indices" }

dlg:button {
    id="analyze",
    text = "ANALYZE",
    onclick = function() 
    --        math.randomseed(os.time())

        local cel = app.activeCel
        local img = getImg(cel) -- if an img is returned, it is valid
        if img == nil then
            return
        end

        local ccx = img.width/16
        local ccy = img.height/16
        vprint( 1, string.format("Image is %dx%d and therefore composed of %dx%d tiles.", img.width,img.height,ccx,ccy ) )
            
        local pal = app.activeSprite.palettes[1]

        local apals = buildPals(pal)
        
        vprint( 1, string.format("Found %s colors in palette.", tostring(#pal) ) )

        local col
        local idx

        local selection = Selection()

        for ty=0, ccy-1 do
            for tx=0, ccx-1 do
                -- process tile
                vprint( 2, string.format("Processing tile [ %d , %d ]", tx, ty ) )
              
                -- try to find the best palette by counting how many hits are found per pixels
                local bestpal = getTileBestPal(tx,ty,img,pal,apals)
                                
                if bestpal == -1 then
                    -- found a problematic tile
                    selection:add( Rectangle(tx*16, ty*16, 16, 16) )
                end
            end
        end

        if selection.isEmpty then
            app.alert{title="Info", text="All tiles are mapped to a single 4 colors palette.", buttons="OK"}
        end

        -- Here we apply the selection
        cel.sprite.selection = selection
        -- Here we redraw the screen to show the modified pixels, in a future
        -- this shouldn't be necessary, but just in case...
        app.refresh()
    end
}

dlg:separator{ id="remaping section", text="Remap Indices" }

local function remapTile(tx,ty,img,pal,apals,bestpal)
    local tsy = ty*16
    local tsx = tx*16
    local col
    local idx

    for y=tsy, tsy+15 do
        for x=tsx, tsx+15 do
            idx = img:getPixel(x,y)
            col = pal:getColor(idx)

            local newidx = getColorIndex(col,apals[bestpal])

            img:putPixel(x,y,bestpal*4+newidx)
            
            vprint( 3, string.format("idx %d => #%02x%02x%02x", idx, col.red, col.green,col.blue) )
        end
    end
end

dlg:button {
    id="remap",
    text = "REMAP",
    onclick = function()
--        math.randomseed(os.time())

        local cel = app.activeCel
        local img = getImg(cel) -- if an img is returned, it is valid
        if img == nil then
            return
        end

        local ccx = img.width/16
        local ccy = img.height/16
        vprint( 1, string.format("Image is %dx%d and therefore composed of %dx%d tiles.", img.width,img.height,ccx,ccy ) )
              
        local pal = app.activeSprite.palettes[1]

        local apals = buildPals(pal)
        
        vprint( 1, string.format("Found %s colors in palette.", tostring(n) ) )

        local col
        local idx

        for ty=0, ccy-1 do
            for tx=0, ccx-1 do
                -- process tile
                vprint( 2, string.format("Processing tile [ %d , %d ]", tx, ty ) )
              
                -- try to find the best palette by counting how many hits are found per pixels
                local bestpal = getTileBestPal(tx,ty,img,pal,apals)
                                
                if bestpal ~= -1 then
                    vprint( 2, string.format("Best palette is #%d", bestpal) )
                    -- remap now
                    remapTile(tx,ty,img,pal,apals,bestpal)
                else 
                    return app.alert{ title="Error", text=string.format("Cannot find best palette for cell [ %d , %d ]. Too many colors in cell or colors not found in palette.", tx,ty), buttons="OK" }
                end
            end
        end
        -- Here we change the cel image, this generates one undoable action
        cel.image = img
        -- Here we redraw the screen to show the modified pixels, in a future
        -- this shouldn't be necessary, but just in case...
        app.refresh()
    end
}

dlg:separator{ id="debug", text="DEBUG" }

dlg:check{ id="verbose_mode",
           label="verbose",
           text="",
           selected=false }
dlg:slider{ id="verbose_level",
           label="level",
           min=0,
           max=3,
           value=1
}
           

dlg:newrow()

dlg:button {
    id = "cancel",
    text = "CANCEL",
    onclick = function()
        vprint(1, "Goodbye!")
        dlg:close()
    end
}

dlg:show { wait = false }
