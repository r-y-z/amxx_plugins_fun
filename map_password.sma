#include <amxmodx>
#include <engine>
#include <fakemeta>

#define PLUGIN_NAME    "地图密码门提示"
#define PLUGIN_VERSION "2.4"
#define PLUGIN_AUTHOR  "yuqi"

#define NAME_LEN 64
#define MAX_SEQ  64

#define TASK_FLASH 918273

#define FLASH_RADIUS 240.0
#define FLASH_ON      3
#define FLASH_GAP     3
#define FLASH_CYCLE  15
#define FLASH_AMOUNT 120.0

#define SCAN_WAIT   10
#define SCAN_GIVEUP 60

enum _:TableData
{
	TABLE_GROUP,
	TABLE_BTN,
	TABLE_CT,
	TABLE_SEQ,
	TABLE_HINT,
	TABLE_MARK,
	TABLE_SIZE
}

enum _:BtnData
{
	BTN_ENT,
	BTN_NAME,
	BTN_TARGET,
	BTN_STATE,
	BTN_SIZE
}

enum _:CtData
{
	CT_NAME,
	CT_BTN,
	CT_NEW,
	CT_SIZE
}

enum _:HintData
{
	HINT_LEN,
	HINT_X,
	HINT_Y,
	HINT_Z,
	HINT_GID,
	HINT_SIZE
}

enum _:FlashData
{
	FL_HINT,
	FL_STEP,
	FL_STAGE,
	FL_TIMER,
	FL_ENT,
	FL_MODE,
	FL_FX,
	FL_AMT,
	FL_SIZE
}

enum _:ScanData
{
	SC_READY,
	SC_WAIT,
	SC_TRIES,
	SC_SIZE
}

new g_table[TABLE_SIZE]
new g_flash[FL_SIZE]
new Float:g_flash_color[3]
new g_scan[SC_SIZE]
new g_map[32]
new g_gen

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)

	g_table[TABLE_GROUP] = _:ArrayCreate(NAME_LEN)
	g_table[TABLE_BTN] = _:ArrayCreate(1)
	g_table[TABLE_CT] = _:ArrayCreate(1)
	g_table[TABLE_SEQ] = _:ArrayCreate(1)
	g_table[TABLE_HINT] = _:ArrayCreate(1)
	g_table[TABLE_MARK] = _:ArrayCreate(1)

	g_flash[FL_HINT] = -1
	g_flash[FL_ENT] = -1

	set_task(0.1, "task_flash", TASK_FLASH, _, _, "b")
}

public plugin_end()
{
	flash_cancel()
}

public task_flash()
{
	if (sync_map())
		return

	if (!g_scan[SC_READY])
	{
		if (g_scan[SC_WAIT] > 0)
		{
			g_scan[SC_WAIT]--
			return
		}
		g_scan[SC_WAIT] = SCAN_WAIT
		if (build_table())
		{
			g_scan[SC_READY] = 1
			solve_keypads()
		}
		else if (++g_scan[SC_TRIES] >= SCAN_GIVEUP)
			g_scan[SC_READY] = 1
		return
	}

	if (ArraySize(table(TABLE_HINT)) == 0)
	{
		flash_cancel()
		return
	}

	if (g_flash[FL_ENT] != -1)
	{
		if (--g_flash[FL_TIMER] > 0)
			return
		flash_restore()
		if (g_flash[FL_STEP] + 1 < ArrayGetCell(table(TABLE_HINT), g_flash[FL_HINT] + HINT_LEN))
		{
			g_flash[FL_STAGE] = 1
			g_flash[FL_TIMER] = FLASH_GAP
		}
		else
		{
			g_flash[FL_STAGE] = 2
			g_flash[FL_TIMER] = FLASH_CYCLE
		}
		return
	}

	if (g_flash[FL_HINT] != -1)
	{
		if (--g_flash[FL_TIMER] > 0)
			return
		if (g_flash[FL_STAGE] == 1)
		{
			g_flash[FL_STEP]++
			flash_on()
		}
		else
		{
			g_flash[FL_HINT] = -1
		}
		return
	}

	new hint = find_near_hint()
	if (hint == -1)
		return
	g_flash[FL_HINT] = hint
	g_flash[FL_STEP] = 0
	flash_on()
}

build_table()
{
	ArrayClear(table(TABLE_GROUP))
	ArrayClear(table(TABLE_BTN))
	ArrayClear(table(TABLE_CT))
	ArrayClear(table(TABLE_MARK))

	new name[NAME_LEN], target[NAME_LEN]

	for (new ent = 0; (ent = find_ent_by_class(ent, "func_button")) > 0;)
	{
		pev(ent, pev_targetname, name, charsmax(name))
		if (name[0] == 0)
			continue
		pev(ent, pev_target, target, charsmax(target))

		new tgid = group_id(target)
		ArrayPushCell(table(TABLE_BTN), ent)
		ArrayPushCell(table(TABLE_BTN), group_id(name))
		ArrayPushCell(table(TABLE_BTN), tgid)
		ArrayPushCell(table(TABLE_BTN), tgid)
	}

	for (new ent = 0; (ent = find_ent_by_class(ent, "trigger_changetarget")) > 0;)
		probe_ct(ent)

	for (new i = 0; i < ArraySize(table(TABLE_GROUP)); i++)
		ArrayPushCell(table(TABLE_MARK), 0)

	return ct_count() > 0 ? 1 : 0
}

probe_ct(ent)
{
	new name[NAME_LEN], tname[NAME_LEN]
	pev(ent, pev_targetname, name, charsmax(name))
	pev(ent, pev_target, tname, charsmax(tname))
	if (name[0] == 0 || tname[0] == 0)
		return

	new b = find_btn_by_name(tname)
	if (b == -1)
		return

	new btn = btn_get(b, BTN_ENT)
	new orig = pev(btn, pev_target)

	new sentinel = engfunc(EngFunc_AllocString, "map_password_probe")
	set_pev_string(btn, pev_target, sentinel)

	dllfunc(DLLFunc_Use, ent, ent)

	new now = pev(btn, pev_target)
	if (now == sentinel)
	{
		set_pev_string(btn, pev_target, orig)
		return
	}

	new newtarget[NAME_LEN]
	pev(btn, pev_target, newtarget, charsmax(newtarget))
	set_pev_string(btn, pev_target, orig)

	ArrayPushCell(table(TABLE_CT), group_id(name))
	ArrayPushCell(table(TABLE_CT), b)
	ArrayPushCell(table(TABLE_CT), group_id(newtarget))
}

sync_map()
{
	new map[32]
	get_mapname(map, charsmax(map))
	if (equal(map, g_map))
		return 0

	flash_forget()
	clear_hints()
	g_scan[SC_READY] = 0
	g_scan[SC_WAIT] = 0
	g_scan[SC_TRIES] = 0
	copy(g_map, charsmax(g_map), map)
	return 1
}

solve_keypads()
{
	flash_cancel()
	clear_hints()

	if (ct_count() == 0 || btn_count() == 0)
		return

	new ctlen = ct_count()

	for (new i = 0; i < ctlen; i++)
	{
		if (ct_get(i, CT_BTN) == -1)
			continue

		new gid = ct_get(i, CT_NEW)
		if (gid == -1 || is_ct_name(gid) || hint_exists(gid))
			continue

		new stop
		walk_back(gid, stop)
		if (seq_size() < 2)
			continue

		if (!simulate(gid))
		{
			new first = find_btn_by_target(stop)
			if (first == -1 || seq_size() >= MAX_SEQ)
				continue
			seq_prepend(first)
			if (!simulate(gid))
				continue
		}

		store_hint(gid)
	}
}

walk_back(terminal, &stop)
{
	new cur = terminal
	new ctlen = ct_count()

	ArrayClear(table(TABLE_SEQ))
	g_gen++
	mark(cur)

	while (seq_size() < MAX_SEQ)
	{
		new found = -1

		for (new i = 0; i < ctlen; i++)
		{
			if (ct_get(i, CT_BTN) == -1)
				continue
			if (ct_get(i, CT_NEW) != cur)
				continue
			if (marked(ct_get(i, CT_NAME)))
				continue
			found = i
			break
		}

		if (found == -1)
			break

		seq_prepend(ct_get(found, CT_BTN))
		cur = ct_get(found, CT_NAME)
		mark(cur)
	}

	stop = cur
	return seq_size() > 0 ? 1 : 0
}

simulate(terminal)
{
	new count = btn_count()
	for (new b = 0; b < count; b++)
		btn_set(b, BTN_STATE, btn_get(b, BTN_TARGET))

	new steps = seq_size()
	new ctlen = ct_count()
	new last = -1

	for (new p = 0; p < steps; p++)
	{
		new b = ArrayGetCell(table(TABLE_SEQ), p)
		last = btn_get(b, BTN_STATE)

		for (new i = 0; i < ctlen; i++)
		{
			if (ct_get(i, CT_NAME) != last)
				continue
			new t = ct_get(i, CT_BTN)
			if (t == -1)
				continue
			btn_set(t, BTN_STATE, ct_get(i, CT_NEW))
		}
	}

	return last == terminal
}

store_hint(gid)
{
	new steps = seq_size()
	if (steps < 1)
		return

	new Float:sum[3] = {0.0, 0.0, 0.0}
	new Float:center[3]

	for (new i = 0; i < steps; i++)
	{
		new ent = btn_get(ArrayGetCell(table(TABLE_SEQ), i), BTN_ENT)
		if (!pev_valid(ent))
			return
		get_entity_center(ent, center)
		sum[0] += center[0]
		sum[1] += center[1]
		sum[2] += center[2]
	}

	new Float:inv = 1.0 / float(steps)
	ArrayPushCell(table(TABLE_HINT), steps)
	ArrayPushCell(table(TABLE_HINT), _:(sum[0] * inv))
	ArrayPushCell(table(TABLE_HINT), _:(sum[1] * inv))
	ArrayPushCell(table(TABLE_HINT), _:(sum[2] * inv))
	ArrayPushCell(table(TABLE_HINT), gid)

	for (new i = 0; i < steps; i++)
		ArrayPushCell(table(TABLE_HINT), btn_get(ArrayGetCell(table(TABLE_SEQ), i), BTN_ENT))
}

clear_hints()
{
	ArrayClear(table(TABLE_HINT))
}

flash_on()
{
	flash_restore()

	new ent = ArrayGetCell(table(TABLE_HINT), g_flash[FL_HINT] + HINT_SIZE + g_flash[FL_STEP])
	if (ent <= 0 || !pev_valid(ent))
	{
		g_flash[FL_HINT] = -1
		return
	}

	g_flash[FL_ENT] = ent
	g_flash[FL_MODE] = pev(ent, pev_rendermode)
	g_flash[FL_FX] = pev(ent, pev_renderfx)
	g_flash[FL_AMT] = _:Float:pev(ent, pev_renderamt)
	pev(ent, pev_rendercolor, g_flash_color)

	new Float:red[3] = {255.0, 0.0, 0.0}
	set_pev(ent, pev_renderfx, kRenderFxNone)
	set_pev(ent, pev_rendermode, kRenderTransColor)
	set_pev(ent, pev_renderamt, FLASH_AMOUNT)
	set_pev(ent, pev_rendercolor, red)

	g_flash[FL_STAGE] = 0
	g_flash[FL_TIMER] = FLASH_ON
}

flash_restore()
{
	if (g_flash[FL_ENT] > 0 && pev_valid(g_flash[FL_ENT]))
	{
		set_pev(g_flash[FL_ENT], pev_rendermode, g_flash[FL_MODE])
		set_pev(g_flash[FL_ENT], pev_renderfx, g_flash[FL_FX])
		set_pev(g_flash[FL_ENT], pev_renderamt, Float:g_flash[FL_AMT])
		set_pev(g_flash[FL_ENT], pev_rendercolor, g_flash_color)
	}
	g_flash[FL_ENT] = -1
}

flash_cancel()
{
	flash_restore()
	g_flash[FL_HINT] = -1
}

flash_forget()
{
	g_flash[FL_ENT] = -1
	g_flash[FL_HINT] = -1
}

find_near_hint()
{
	new size = ArraySize(table(TABLE_HINT))
	if (size == 0)
		return -1

	new best = -1
	new Float:best_dist = FLASH_RADIUS + 1.0

	for (new id = 1; id <= get_maxplayers(); id++)
	{
		if (!is_user_connected(id))
			continue

		new Float:origin[3]
		pev(id, pev_origin, origin)

		for (new pos = 0; pos < size; pos += HINT_SIZE + ArrayGetCell(table(TABLE_HINT), pos))
		{
			new Float:center[3]
			center[0] = Float:ArrayGetCell(table(TABLE_HINT), pos + HINT_X)
			center[1] = Float:ArrayGetCell(table(TABLE_HINT), pos + HINT_Y)
			center[2] = Float:ArrayGetCell(table(TABLE_HINT), pos + HINT_Z)
			new Float:dist = get_distance_f(origin, center)
			if (dist <= FLASH_RADIUS && dist < best_dist)
			{
				best = pos
				best_dist = dist
			}
		}
	}

	return best
}

stock Array:table(id)
{
	return Array:g_table[id]
}

stock btn_count()
{
	return ArraySize(table(TABLE_BTN)) / BTN_SIZE
}

stock ct_count()
{
	return ArraySize(table(TABLE_CT)) / CT_SIZE
}

stock btn_get(idx, field)
{
	return ArrayGetCell(table(TABLE_BTN), idx * BTN_SIZE + field)
}

stock btn_set(idx, field, value)
{
	ArraySetCell(table(TABLE_BTN), idx * BTN_SIZE + field, value)
}

stock ct_get(idx, field)
{
	return ArrayGetCell(table(TABLE_CT), idx * CT_SIZE + field)
}

stock seq_size()
{
	return ArraySize(table(TABLE_SEQ))
}

group_id(const name[])
{
	if (name[0] == 0)
		return -1

	new count = ArraySize(table(TABLE_GROUP))
	new buf[NAME_LEN]
	for (new i = 0; i < count; i++)
	{
		ArrayGetString(table(TABLE_GROUP), i, buf, charsmax(buf))
		if (equali(buf, name))
			return i
	}
	ArrayPushString(table(TABLE_GROUP), name)
	return count
}

find_btn_by_name(const name[])
{
	new count = btn_count()
	new buf[NAME_LEN]
	for (new b = 0; b < count; b++)
	{
		ArrayGetString(table(TABLE_GROUP), btn_get(b, BTN_NAME), buf, charsmax(buf))
		if (equali(buf, name))
			return b
	}
	return -1
}

find_btn_by_target(gid)
{
	new count = btn_count()
	for (new b = 0; b < count; b++)
	{
		if (btn_get(b, BTN_TARGET) == gid)
			return b
	}
	return -1
}

is_ct_name(gid)
{
	new count = ct_count()
	for (new i = 0; i < count; i++)
	{
		if (ct_get(i, CT_NAME) == gid)
			return 1
	}
	return 0
}

hint_exists(gid)
{
	new size = ArraySize(table(TABLE_HINT))
	for (new pos = 0; pos < size; pos += HINT_SIZE + ArrayGetCell(table(TABLE_HINT), pos))
	{
		if (ArrayGetCell(table(TABLE_HINT), pos + HINT_GID) == gid)
			return 1
	}
	return 0
}

seq_prepend(btn)
{
	if (seq_size() == 0)
		ArrayPushCell(table(TABLE_SEQ), btn)
	else
		ArrayInsertCellBefore(table(TABLE_SEQ), 0, btn)
}

mark(gid)
{
	ArraySetCell(table(TABLE_MARK), gid, g_gen)
}

marked(gid)
{
	return ArrayGetCell(table(TABLE_MARK), gid) == g_gen
}

get_entity_center(ent, Float:out[3])
{
	new Float:mins[3], Float:maxs[3], Float:org[3]
	pev(ent, pev_absmin, mins)
	pev(ent, pev_absmax, maxs)
	pev(ent, pev_origin, org)

	out[0] = (mins[0] + maxs[0]) * 0.5
	out[1] = (mins[1] + maxs[1]) * 0.5
	out[2] = (mins[2] + maxs[2]) * 0.5

	if (mins[0] == maxs[0] && mins[1] == maxs[1] && mins[2] == maxs[2])
	{
		out[0] = org[0]
		out[1] = org[1]
		out[2] = org[2]
	}
}
