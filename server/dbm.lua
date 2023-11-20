-- Get CitizenIDs from Player License
function GetCitizenID(license)
    local result = MySQL.query.await("SELECT identifier FROM players WHERE license = ?", {license,})
    if result ~= nil then
        return result
    else
        print("Cannot find a identifier for License: "..license)
        return nil
    end
end

-- (Start) Opening the MDT and sending data
function AddLog(text)
    return MySQL.insert.await('INSERT INTO `mdt_logs` (`text`, `time`) VALUES (?,?)', {text, os.time() * 1000})
end

function GetNameFromId(identifier)
	local result = MySQL.scalar.await('SELECT charinfo FROM players WHERE identifier = @identifier', { ['@identifier'] = identifier })
    if result ~= nil then
        local charinfo = json.decode(result)
        local fullname = charinfo['firstname']..' '..charinfo['lastname']
        return fullname
    else
        --print('Player does not exist')
        return nil
    end
end

function GetPersonInformation(identifier, jobtype)
    local result = MySQL.query.await('SELECT information, tags, gallery, pfp, fingerprint FROM mdt_data WHERE identifier = ? and jobtype = ?', { identifier,  jobtype})
    return result[1]
end

function GetIncidentName(id)
	local result = MySQL.query.await('SELECT title FROM `mdt_incidents` WHERE id = :id LIMIT 1', { id = id })
    return result[1]
end

function GetConvictions(cids)
	return MySQL.query.await('SELECT * FROM `mdt_convictions` WHERE `identifier` IN(?)', { cids })
end

function GetLicenseInfo(identifier)
	local result = MySQL.query.await('SELECT * FROM `licenses` WHERE `identifier` = ?', { identifier })
	return result
end

function CreateUser(identifier, tableName)
	AddLog("A user was created with the identifier: "..identifier)
	return MySQL.insert.await("INSERT INTO `"..tableName.."` (identifier) VALUES (:identifier)", { identifier = identifier })
end

function GetPlayerVehicles(identifier)
	local vehicleList =  MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {identifier})
    if vehicleList then
        for k, veh in pairs(vehicleList) do
            veh.vehicle = json.decode(veh.vehicle)
            local modelName = GetVehicleHashByName(veh.vehicle.model)
            local infos = MySQL.single.await("SELECT * FROM vehicles WHERE model = ?", {modelName})
            if infos == nil then
                print(veh.vehicle.model)
            end
            veh.infos = infos
            veh.adv_stats = json.decode(veh.adv_stats)
        end
	    return vehicleList
    end
end

function GetBulletins(JobType)
	return MySQL.query.await('SELECT * FROM `mdt_bulletin` WHERE `jobtype` = ? LIMIT 10', { JobType })
end

function GetPlayerProperties(identifier, cb)
	local result =  MySQL.query.await('SELECT houselocations.label, houselocations.coords FROM player_houses INNER JOIN houselocations ON player_houses.house = houselocations.name where player_houses.identifier = ?', {identifier})
	return result
end

function GetPlayerDataById(id)
    local Player = ESX.GetPlayerFromIdentifier(id)
    if Player ~= nil then
		local response = {identifier = Player.PlayerData.identifier, charinfo = Player.PlayerData.charinfo, metadata = Player.PlayerData.metadata, job = Player.PlayerData.job}
        return response
    else
        return MySQL.single.await('SELECT identifier, charinfo, job, metadata FROM players WHERE identifier = ? LIMIT 1', { id })
    end
end

function GetBoloStatus(plate)
	local result = MySQL.scalar.await('SELECT id FROM `mdt_bolos` WHERE LOWER(`plate`)=:plate', { plate = string.lower(plate)})
	return result
end

function GetOwnerName(identifier)
	local result = MySQL.scalar.await('SELECT charinfo FROM `players` WHERE LOWER(`identifier`) = ? LIMIT 1', {identifier})
	return result
end

function GetVehicleInformation(plate, cb)
    local result = MySQL.query.await('SELECT id, information FROM `mdt_vehicleinfo` WHERE plate=:plate', { plate = plate})
	cb(result)
end

function GetPlayerApartment(identifier, cb)
    local result =  MySQL.query.await('SELECT * FROM `player_houses` WHERE identifier = ?', {identifier})
    return result
end

function GetPlayerLicenses(identifier)
    return MySQL.query.await('SELECT user_licenses.type, licenses.label FROM user_licenses LEFT JOIN licenses ON user_licenses.type = licenses.type WHERE owner = ?', {identifier})
end

function GetAllLicenses()
    local res = MySQL.query.await('SELECT * FROM licenses', {})
    local formattedLicences = {}

    for k, v in pairs(res) do
        formattedLicences[v.type] = { label = v.label, type = v.type, status = false }
    end

    return formattedLicences
end

-- function GetPlayerLicenses(identifier)
--     local response = false
--     local Player = ESX.GetPlayerFromIdentifier(identifier)
--     if Player ~= nil then
--         return Player.PlayerData.metadata.licences
--     else
--         local result = MySQL.scalar.await('SELECT metadata FROM players WHERE identifier = @identifier', {['@identifier'] = identifier})
--         if result ~= nil then
--             local metadata = json.decode(result)
--             if metadata["licences"] ~= nil and metadata["licences"] then
--                 return metadata["licences"]
--             else
--                 return {
--                     ['driver'] = false,
--                     ['business'] = false,
--                     ['weapon'] = false,
--                     ['pilot'] = false
--                 }
--             end
--         end
--     end
-- end

function ManageLicense(identifier, type, status)
    local Player = ESX.GetPlayerFromIdentifier(identifier)
    local licenseStatus = nil
    if status == "give" then licenseStatus = true elseif status == "revoke" then licenseStatus = false end
    if Player ~= nil then
        local licences = Player.PlayerData.metadata["licences"]
        local newLicenses = {}
        for k, v in pairs(licences) do
            local status = v
            if k == type then
                status = licenseStatus
            end
            newLicenses[k] = status
        end
        Player.Functions.SetMetaData("licences", newLicenses)
    else
        local licenseType = '$.licences.'..type
        local result = MySQL.query.await('UPDATE `players` SET `metadata` = JSON_REPLACE(`metadata`, ?, ?) WHERE `identifier` = ?', {licenseType, licenseStatus, identifier}) --seems to not work on older MYSQL versions, think about alternative
    end
end

function UpdateAllLicenses(identifier, incomingLicenses)
    local Player = ESX.GetPlayerFromIdentifier(identifier)
    if Player ~= nil then
        Player.Functions.SetMetaData("licences", incomingLicenses)

    else
        local result = MySQL.scalar.await('SELECT metadata FROM players WHERE identifier = @identifier', {['@identifier'] = identifier})
        result = json.decode(result)

        result.licences = result.licences or {
            ['driver'] = true,
            ['business'] = false,
            ['weapon'] = false,
            ['pilot'] = false
        }

        for k, _ in pairs(incomingLicenses) do
            result.licences[k] = incomingLicenses[k]
        end
        MySQL.query.await('UPDATE `players` SET `metadata` = @metadata WHERE identifier = @identifier', {['@metadata'] = json.encode(result), ['@identifier'] = identifier})
    end
end

function GetAllLicenses()
    local res = MySQL.query.await('SELECT * FROM licenses', {})
    local formattedLicences = {}

    for k, v in pairs(res) do
        formattedLicences[v.type] = { label = v.label, type = v.type, status = false }
    end

    return formattedLicences
end

-- function RetrieveVehiclesFromDB()
-- 	local vehicles = MySQL.query.await('SELECT * FROM vehicles')
--     for k, v in pairs(vehicles) do
--         if Config.vModelByHash[joaat(v.model)] == nil then
--             Config.vModelByHash[joaat(v.model)] = v.model
--         end
--     end
-- end

function GetVehiclesFromDB()
    local vehicles = MySQL.query.await('SELECT * FROM `vehicles`')

    for k, v in pairs(vehicles) do
        if VEHICLESTOHASH[string.lower(v.model)] == nil then
            --print(string.lower(v.model), joaat(string.lower(v.model)))
            VEHICLESTOHASH[string.lower(v.model)] = joaat(string.lower(v.model))
        end
        if HASHTOVEHICLE[joaat(string.lower(v.model))] == nil then
            --print(joaat(string.lower(v.model)), string.lower(v.model))
            HASHTOVEHICLE[joaat(string.lower(v.model))] = string.lower(v.model)
        end
    end

    local VEHICLESTOHASHCOUNT = 0
    for k, v in pairs(VEHICLESTOHASH) do
        VEHICLESTOHASHCOUNT += 1
    end

    local HASHTOVEHICLECOUNT = 0
    for k, v in pairs(HASHTOVEHICLE) do
        HASHTOVEHICLECOUNT += 1
    end

    print(VEHICLESTOHASHCOUNT)
    print(HASHTOVEHICLECOUNT)
end

