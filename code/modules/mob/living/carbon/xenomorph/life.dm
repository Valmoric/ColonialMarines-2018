#define DEBUG_XENO_LIFE	0
#define XENO_RESTING_HEAL 1
#define XENO_STANDING_HEAL 0.2
#define XENO_CRIT_DAMAGE 5

/mob/living/carbon/Xenomorph/Life()

	if(monkeyizing || !loc)
		return

	..()

	if(stat == DEAD) //Dead, nothing else to do.
		return
	if(stat == UNCONSCIOUS)
		if(is_zoomed)
			zoom_out()
	else
		if(is_zoomed)
			if(loc != zoom_turf || lying)
				zoom_out()
		update_progression()
		update_evolving()
		handle_aura_emiter()

	handle_aura_receiver()
	handle_living_health_updates()
	handle_living_plasma_updates()
	update_action_button_icons()
	update_icons()

/mob/living/carbon/Xenomorph/update_stat()

	update_cloak()

	if(status_flags & GODMODE)
		return

	if(stat == DEAD)
		return

	if(health <= crit_health)
		if(prob(gib_chance + 0.5*(crit_health - health)))
			gib()
		else
			death()
		return

	if(knocked_out || sleeping || health < 0)
		stat = UNCONSCIOUS
		see_in_dark = 5
	else
		stat = CONSCIOUS
		see_in_dark = 8
	update_canmove()

	//Deal with devoured things and people
	if(stomach_contents.len)
		for(var/atom/movable/M in stomach_contents)
			if(world.time > devour_timer && ishuman(M) && !is_ventcrawling)
				stomach_contents.Remove(M)
				if(M.loc != src)
					continue
				M.forceMove(loc)
	return TRUE

/mob/living/carbon/Xenomorph/Runner/update_stat()
	. = ..()
	if(stat != CONSCIOUS && layer != initial(layer))
		layer = MOB_LAYER

/mob/living/carbon/Xenomorph/Boiler/update_stat()
	. = ..()
	if(stat == CONSCIOUS)
		see_in_dark = 20

/mob/living/carbon/Xenomorph/handle_status_effects()
	. = ..()
	handle_stagger() // 1 each time
	handle_slowdown() // 0.4 each time
	handle_halloss() // 3 each time

/mob/living/carbon/Xenomorph/proc/handle_critical_health_updates()
	var/turf/T = loc
	if(istype(T))
		if(!locate(/obj/effect/alien/weeds) in T) //In crit, damage is maximal if you're caught off weeds
			adjustBruteLoss(2.5 - warding_aura*0.5) //Warding can heavily lower the impact of bleedout. Halved at 2.5 phero, stopped at 5 phero
		else
			adjustBruteLoss(-warding_aura*0.5) //Warding pheromones provides 0.25 HP per second per step, up to 2.5 HP per tick.

/mob/living/carbon/Xenomorph/handle_fire()
	if(..())
		return
	if(!fire_immune)
		adjustFireLoss(fire_stacks + 3)

/mob/living/carbon/Xenomorph/proc/handle_living_health_updates()
	if(health >= maxHealth || hardcore) //no damage, don't bother
		updatehealth() //Update health-related stats, like health itself (using brute and fireloss), health HUD and status.
		return
	var/turf/T = loc
	if(!T || !istype(T)) //where are we?
		return
	if(innate_healing) //Larvas regenerate fast anywhere as long as not in crit.
		if(!(locate(/obj/effect/alien/weeds) in T) && health <= 0)
			adjustBruteLoss(XENO_CRIT_DAMAGE)
		else
			heal_wounds(XENO_RESTING_HEAL)
		updatehealth()
		return
	var/datum/hive_status/hive = hive_datum[hivenumber]
	if(hive.living_xeno_queen && hive.living_xeno_queen.loc.z != loc.z) //if there is a queen, it must be in the same z-level
		updatehealth()
		return
	if(locate(/obj/effect/alien/weeds) in T) //We regenerate on weeds.
		if(lying || resting)
			heal_wounds(XENO_RESTING_HEAL)
		else
			heal_wounds(XENO_STANDING_HEAL) //Major healing nerf if standing.
	else if(health <= 0)
		adjustBruteLoss(XENO_CRIT_DAMAGE) //Crit and no weeds makes us bleed.
	updatehealth()

/mob/living/carbon/Xenomorph/proc/heal_wounds(multiplier = XENO_RESTING_HEAL)
	var/amount = (1 + (maxHealth * 0.02) ) // 1 damage + 2% max health
	if(recovery_aura)
		amount += recovery_aura * maxHealth * 0.01 // +1% max health per recovery level, up to +5%
	amount *= multiplier
	adjustBruteLoss(-amount)
	adjustFireLoss(-amount)

/mob/living/carbon/Xenomorph/Xenoborg/handle_living_health_updates()
	updatehealth()
	return

/mob/living/carbon/Xenomorph/proc/handle_living_plasma_updates()
	var/turf/T = loc
	if(!T || !istype(T))
		return
	if(current_aura)
		plasma_stored -= 5
	if(plasma_stored == plasma_max)
		return
	if(locate(/obj/effect/alien/weeds) in T)
		plasma_stored += plasma_gain
		if(recovery_aura)
			plasma_stored += round(plasma_gain * recovery_aura * 0.25) //Divided by four because it gets massive fast. 1 is equivalent to weed regen! Only the strongest pheromones should bypass weeds
	else
		plasma_stored++
	if(plasma_stored > plasma_max)
		plasma_stored = plasma_max
	else if(plasma_stored < 0)
		plasma_stored = 0
		if(current_aura)
			current_aura = null
			to_chat(src, "<span class='warning'>You have ran out of plasma and stopped emitting pheromones.</span>")

	hud_set_plasma() //update plasma amount on the plasma mob_hud


/mob/living/carbon/Xenomorph/Hivelord/handle_living_plasma_updates()
	if(speed_activated)
		plasma_stored -= 30
		if(plasma_stored < 0)
			speed_activated = FALSE
			to_chat(src, "<span class='warning'>You feel dizzy as the world slows down.</span>")
	..()

/mob/living/carbon/Xenomorph/Xenoborg/handle_living_plasma_updates()
	return

/mob/living/carbon/Xenomorph/proc/handle_aura_emiter()
	//Rollercoaster of fucking stupid because Xeno life ticks aren't synchronised properly and values reset just after being applied
	//At least it's more efficient since only Xenos with an aura do this, instead of all Xenos
	//Basically, we use a special tally var so we don't reset the actual aura value before making sure they're not affected
	if(current_aura && plasma_stored > 5)
		if(caste == "Queen" && anchored) //stationary queen's pheromone apply around the observed xeno.
			var/mob/living/carbon/Xenomorph/Queen/Q = src
			var/atom/phero_center = Q
			if(Q.observed_xeno)
				phero_center = Q.observed_xeno
			var/pheromone_range = round(6 + aura_strength * 2)
			for(var/mob/living/carbon/Xenomorph/Z in range(pheromone_range, phero_center)) //Goes from 8 for Queen to 16 for Ancient Queen
				if(Z.stat != DEAD && hivenumber == Z.hivenumber)
					switch(current_aura)
						if("frenzy")
							if(aura_strength > Z.frenzy_new)
								Z.frenzy_new = aura_strength
						if("warding")
							if(aura_strength > Z.warding_new)
								Z.warding_new = aura_strength
						if("recovery")
							if(aura_strength > Z.recovery_new)
								Z.recovery_new = aura_strength
		else
			var/pheromone_range = round(6 + aura_strength * 2)
			for(var/mob/living/carbon/Xenomorph/Z in range(pheromone_range, src)) //Goes from 7 for Young Drone to 16 for Ancient Queen
				if(Z.stat != DEAD && hivenumber == Z.hivenumber)
					switch(current_aura)
						if("frenzy")
							if(aura_strength > Z.frenzy_new)
								Z.frenzy_new = aura_strength
						if("warding")
							if(aura_strength > Z.warding_new)
								Z.warding_new = aura_strength
						if("recovery")
							if(aura_strength > Z.recovery_new)
								Z.recovery_new = aura_strength
		if(leader_current_aura && !stat)
			var/pheromone_range = round(6 + leader_aura_strength * 2)
			for(var/mob/living/carbon/Xenomorph/Z in range(pheromone_range, src)) //Goes from 7 for Young Drone to 16 for Ancient Queen
				if(Z.stat != DEAD && hivenumber == Z.hivenumber)
					switch(leader_current_aura)
						if("frenzy")
							if(leader_aura_strength > Z.frenzy_new)
								Z.frenzy_new = leader_aura_strength
						if("warding")
							if(leader_aura_strength > Z.warding_new)
								Z.warding_new = leader_aura_strength
						if("recovery")
							if(leader_aura_strength > Z.recovery_new)
								Z.recovery_new = leader_aura_strength

/mob/living/carbon/Xenomorph/proc/handle_aura_receiver()
	if(frenzy_aura != frenzy_new || warding_aura != warding_new || recovery_aura != recovery_new)
		frenzy_aura = frenzy_new
		warding_aura = warding_new
		recovery_aura = recovery_new
		hud_set_pheromone()
	frenzy_new = 0
	warding_new = 0
	recovery_new = 0
	armor_pheromone_bonus = 0
	if(warding_aura > 0)
		armor_pheromone_bonus = warding_aura * 3 //Bonus armor from pheromones, no matter what the armor was previously. Was 5

/mob/living/carbon/Xenomorph/handle_regular_hud_updates()
	if(!client)
		return FALSE
	if(hud_used && hud_used.healths)
		if(stat != DEAD)
			switch(round(health * 100 / maxHealth)) //Maxhealth should never be zero or this will generate runtimes.
				if(100 to INFINITY)
					hud_used.healths.icon_state = "health_full"
				if(94 to 99)
					hud_used.healths.icon_state = "health_16"
				if(88 to 93)
					hud_used.healths.icon_state = "health_15"
				if(82 to 87)
					hud_used.healths.icon_state = "health_14"
				if(76 to 81)
					hud_used.healths.icon_state = "health_13"
				if(70 to 75)
					hud_used.healths.icon_state = "health_12"
				if(64 to 69)
					hud_used.healths.icon_state = "health_11"
				if(58 to 63)
					hud_used.healths.icon_state = "health_10"
				if(52 to 57)
					hud_used.healths.icon_state = "health_9"
				if(46 to 51)
					hud_used.healths.icon_state = "health_8"
				if(40 to 45)
					hud_used.healths.icon_state = "health_7"
				if(34 to 39)
					hud_used.healths.icon_state = "health_6"
				if(28 to 33)
					hud_used.healths.icon_state = "health_5"
				if(22 to 27)
					hud_used.healths.icon_state = "health_4"
				if(16 to 21)
					hud_used.healths.icon_state = "health_3"
				if(10 to 15)
					hud_used.healths.icon_state = "health_2"
				if(4 to 9)
					hud_used.healths.icon_state = "health_1"
				if(0 to 3)
					hud_used.healths.icon_state = "health_0"
				else
					hud_used.healths.icon_state = "health_critical"
		else
			hud_used.healths.icon_state = "health_dead"

	if(hud_used && hud_used.alien_plasma_display)
		if(stat != DEAD)
			if(plasma_max) //No divide by zeros please
				switch(round(plasma_stored * 100 / plasma_max))
					if(100 to INFINITY)
						hud_used.alien_plasma_display.icon_state = "power_display_full"
					if(94 to 99)
						hud_used.alien_plasma_display.icon_state = "power_display_16"
					if(88 to 93)
						hud_used.alien_plasma_display.icon_state = "power_display_15"
					if(82 to 87)
						hud_used.alien_plasma_display.icon_state = "power_display_14"
					if(76 to 81)
						hud_used.alien_plasma_display.icon_state = "power_display_13"
					if(70 to 75)
						hud_used.alien_plasma_display.icon_state = "power_display_12"
					if(64 to 69)
						hud_used.alien_plasma_display.icon_state = "power_display_11"
					if(58 to 63)
						hud_used.alien_plasma_display.icon_state = "power_display_10"
					if(52 to 57)
						hud_used.alien_plasma_display.icon_state = "power_display_9"
					if(46 to 51)
						hud_used.alien_plasma_display.icon_state = "power_display_8"
					if(40 to 45)
						hud_used.alien_plasma_display.icon_state = "power_display_7"
					if(34 to 39)
						hud_used.alien_plasma_display.icon_state = "power_display_6"
					if(28 to 33)
						hud_used.alien_plasma_display.icon_state = "power_display_5"
					if(22 to 27)
						hud_used.alien_plasma_display.icon_state = "power_display_4"
					if(16 to 21)
						hud_used.alien_plasma_display.icon_state = "power_display_3"
					if(10 to 15)
						hud_used.alien_plasma_display.icon_state = "power_display_2"
					if(4 to 9)
						hud_used.alien_plasma_display.icon_state = "power_display_1"
					if(0 to 3)
						hud_used.alien_plasma_display.icon_state = "power_display_0"
					else
						hud_used.alien_plasma_display.icon_state = "power_display_empty"
			else
				hud_used.alien_plasma_display.icon_state = "power_display_empty"
		else
			hud_used.alien_plasma_display.icon_state = "power_display_empty"

		if(interactee)
			interactee.check_eye(src)
		else
			if(client && !client.adminobs)
				reset_view(null)

	if(!stat && prob(25)) //Only a 25% chance of proccing the queen locator, since it is expensive and we don't want it firing every tick
		queen_locator()

	return TRUE

/mob/living/carbon/Xenomorph/proc/handle_environment() //unused while atmos is not on
	var/env_temperature = loc.return_temperature()
	if(!fire_immune)
		if(env_temperature > (T0C + 66))
			adjustFireLoss((env_temperature - (T0C + 66)) / 5) //Might be too high, check in testing.
			updatehealth() //unused while atmos is off
			if(hud_used && hud_used.fire_icon)
				hud_used.fire_icon.icon_state = "fire2"
			if(prob(20))
				to_chat(src, "<span class='warning'>You feel a searing heat!</span>")
		else
			if(hud_used && hud_used.fire_icon)
				hud_used.fire_icon.icon_state = "fire0"

/mob/living/carbon/Xenomorph/proc/queen_locator()
	if(!hud_used || !hud_used.locate_leader)
		return

	var/datum/hive_status/hive
	if(hivenumber && hivenumber <= hive_datum.len)
		hive = hive_datum[hivenumber]
	else
		return

	if(!hive.living_xeno_queen || is_intelligent)
		hud_used.locate_leader.icon_state = "trackoff"
		return

	if(hive.living_xeno_queen.loc.z != loc.z || get_dist(src,hive.living_xeno_queen) < 1 || src == hive.living_xeno_queen)
		hud_used.locate_leader.icon_state = "trackondirect"
	else
		var/area/A = get_area(loc)
		var/area/QA = get_area(hive.living_xeno_queen.loc)
		if(A.fake_zlevel == QA.fake_zlevel)
			hud_used.locate_leader.dir = get_dir(src,hive.living_xeno_queen)
			hud_used.locate_leader.icon_state = "trackon"
		else
			hud_used.locate_leader.icon_state = "trackondirect"

/mob/living/carbon/Xenomorph/updatehealth()
	if(status_flags & GODMODE)
		return
	health = maxHealth - getFireLoss() - getBruteLoss() //Xenos can only take brute and fire damage.
	med_hud_set_health()
	update_stat()




/mob/living/carbon/Xenomorph/handle_stunned()
	if(stunned)
		AdjustStunned(-2)
	return stunned

/mob/living/carbon/Xenomorph/handle_knocked_down()
	if(knocked_down && client)
		AdjustKnockeddown(-5)
	return knocked_down

/mob/living/carbon/Xenomorph/proc/handle_stagger()
	if(stagger)
		#if DEBUG_XENO_LIFE
		world << "<span class='debuginfo'>Regen: Initial stagger is: <b>[stagger]</b></span>"
		#endif
		adjust_stagger(-1)
		#if DEBUG_XENO_LIFE
		world << "<span class='debuginfo'>Regen: Final stagger is: <b>[stagger]</b></span>"
		#endif
	return stagger

/mob/living/carbon/Xenomorph/proc/adjust_stagger(amount)
	stagger = max(stagger + amount,0)
	return stagger

/mob/living/carbon/Xenomorph/proc/handle_slowdown()
	if(slowdown)
		#if DEBUG_XENO_LIFE
		world << "<span class='debuginfo'>Regen: Initial slowdown is: <b>[slowdown]</b></span>"
		#endif
		adjust_slowdown(-XENO_SLOWDOWN_REGEN)
		#if DEBUG_XENO_LIFE
		world << "<span class='debuginfo'>Regen: Final slowdown is: <b>[slowdown]</b></span>"
		#endif
	return slowdown

/mob/living/carbon/Xenomorph/proc/adjust_slowdown(amount)
	slowdown = max(slowdown + amount,0)
	return slowdown

/mob/living/carbon/Xenomorph/proc/add_slowdown(amount)
	slowdown = adjust_slowdown(amount*XENO_SLOWDOWN_REGEN)
	return slowdown

/mob/living/carbon/Xenomorph/proc/handle_halloss()
	if(halloss)
		adjustHalLoss(XENO_HALOSS_REGEN)