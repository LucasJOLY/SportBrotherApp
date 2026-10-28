#!/usr/bin/env python3
"""Construit le catalogue d'exos embarqué.

Liste et groupes : free-exercise-db (domaine public, Unlicense), noms traduits ci-dessous.
Illustrations : animations 3D de l'API gratuite ExerciseDB V1 (AscendAPI), choisies dans exercisedb_media.json.

Usage : python3 -I scripts/build_exercise_catalog.py <dossier_de_travail>
Écrit SportBrother/Resources/ExerciseCatalog/{catalog.json, images/<id>.jpg, anim/<id>.gif}.
Exécuté une seule fois pendant le développement : l'app ne fait aucun appel réseau pour le catalogue.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

SOURCE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main"
MEDIA = "https://static.exercisedb.dev/media"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "SportBrother", "Resources", "ExerciseCatalog")

# id free-exercise-db → nom français. Le groupe vient du muscle principal, sauf mention contraire.
SELECTION = {
    "dos": {
        "Wide-Grip_Lat_Pulldown": "Tirage vertical prise large",
        "Close-Grip_Front_Lat_Pulldown": "Tirage vertical prise serrée",
        "V-Bar_Pulldown": "Tirage vertical triangle",
        "Underhand_Cable_Pulldowns": "Tirage vertical prise supination",
        "One_Arm_Lat_Pulldown": "Tirage vertical un bras",
        "Pullups": "Tractions",
        "Chin-Up": "Tractions supination",
        "Seated_Cable_Rows": "Rowing assis à la poulie",
        "Seated_One-arm_Cable_Pulley_Rows": "Rowing poulie un bras",
        "Bent_Over_Barbell_Row": "Rowing barre buste penché",
        "Reverse_Grip_Bent-Over_Rows": "Rowing barre supination",
        "One-Arm_Dumbbell_Row": "Rowing haltère un bras",
        "Bent_Over_Two-Dumbbell_Row": "Rowing deux haltères",
        "Dumbbell_Incline_Row": "Rowing haltères sur banc incliné",
        "T-Bar_Row_with_Handle": "Rowing T-bar",
        "Lying_T-Bar_Row": "Rowing T-bar allongé",
        "Leverage_High_Row": "Rowing haut à la machine",
        "Leverage_Iso_Row": "Rowing machine convergente",
        "Smith_Machine_Bent_Over_Row": "Rowing à la Smith",
        "Straight-Arm_Pulldown": "Pull-over à la poulie bras tendus",
        "Rope_Straight-Arm_Pulldown": "Pull-over poulie à la corde",
        "Barbell_Deadlift": "Soulevé de terre",
        "Rack_Pulls": "Soulevé de terre partiel (rack pull)",
        "Hyperextensions_With_No_Hyperextension_Bench": "Extensions lombaires",
        "Barbell_Shrug": "Shrugs à la barre",
        "Dumbbell_Shrug": "Shrugs aux haltères",
    },
    "biceps": {
        "Barbell_Curl": "Curl barre",
        "EZ-Bar_Curl": "Curl barre EZ",
        "Close-Grip_EZ_Bar_Curl": "Curl barre EZ prise serrée",
        "Wide-Grip_Standing_Barbell_Curl": "Curl barre prise large",
        "Dumbbell_Bicep_Curl": "Curl haltères",
        "Dumbbell_Alternate_Bicep_Curl": "Curl haltères alterné",
        "Hammer_Curls": "Curl marteau",
        "Alternate_Hammer_Curl": "Curl marteau alterné",
        "Cross_Body_Hammer_Curl": "Curl marteau croisé",
        "Incline_Dumbbell_Curl": "Curl incliné aux haltères",
        "Incline_Hammer_Curls": "Curl marteau incliné",
        "Concentration_Curls": "Curl concentré",
        "Spider_Curl": "Spider curl",
        "Preacher_Curl": "Curl au pupitre",
        "One_Arm_Dumbbell_Preacher_Curl": "Curl pupitre haltère un bras",
        "Machine_Preacher_Curls": "Curl pupitre à la machine",
        "Machine_Bicep_Curl": "Curl biceps à la machine",
        "Standing_Biceps_Cable_Curl": "Curl à la poulie",
        "Cable_Hammer_Curls_-_Rope_Attachment": "Curl marteau à la corde",
        "Cable_Preacher_Curl": "Curl pupitre à la poulie",
        "High_Cable_Curls": "Curl poulie haute",
        "Overhead_Cable_Curl": "Curl poulie vis-à-vis",
        "Reverse_Barbell_Curl": "Curl barre pronation",
        "Drag_Curl": "Drag curl",
        "Zottman_Curl": "Curl Zottman",
    },
    "triceps": {
        "Triceps_Pushdown": "Extension triceps à la poulie",
        "Triceps_Pushdown_-_Rope_Attachment": "Extension triceps à la corde",
        "Triceps_Pushdown_-_V-Bar_Attachment": "Extension triceps barre en V",
        "Reverse_Grip_Triceps_Pushdown": "Extension triceps poulie supination",
        "Cable_One_Arm_Tricep_Extension": "Extension triceps poulie un bras",
        "Triceps_Overhead_Extension_with_Rope": "Extension triceps corde au-dessus de la tête",
        "Cable_Rope_Overhead_Triceps_Extension": "Extension triceps corde nuque",
        "EZ-Bar_Skullcrusher": "Barre au front (skull crusher)",
        "Lying_Triceps_Press": "Barre au front à la barre droite",
        "Lying_Dumbbell_Tricep_Extension": "Extension triceps allongé haltères",
        "Standing_Dumbbell_Triceps_Extension": "Extension triceps haltère debout",
        "Dumbbell_One-Arm_Triceps_Extension": "Extension triceps haltère un bras",
        "Seated_Triceps_Press": "Extension triceps haltère assis",
        "Standing_Overhead_Barbell_Triceps_Extension": "Extension triceps barre au-dessus de la tête",
        "Tricep_Dumbbell_Kickback": "Kickback haltère",
        "Close-Grip_Barbell_Bench_Press": "Développé couché prise serrée",
        "Smith_Machine_Close-Grip_Bench_Press": "Développé couché serré à la Smith",
        "Close-Grip_Dumbbell_Press": "Développé haltères prise serrée",
        "JM_Press": "JM press",
        "Dips_-_Triceps_Version": "Dips triceps",
        "Bench_Dips": "Dips entre deux bancs",
        "Dip_Machine": "Dips à la machine",
        "Machine_Triceps_Extension": "Extension triceps à la machine",
        "Push-Ups_-_Close_Triceps_Position": "Pompes prise serrée",
        "Tate_Press": "Tate press",
    },
    "epaules": {
        "Dumbbell_Shoulder_Press": "Développé épaules haltères",
        "Seated_Dumbbell_Press": "Développé haltères assis",
        "Arnold_Dumbbell_Press": "Développé Arnold",
        "Barbell_Shoulder_Press": "Développé militaire barre assis",
        "Standing_Military_Press": "Développé militaire debout",
        "Machine_Shoulder_Military_Press": "Développé épaules à la machine",
        "Leverage_Shoulder_Press": "Développé épaules machine convergente",
        "Smith_Machine_Overhead_Shoulder_Press": "Développé épaules à la Smith",
        "Cable_Shoulder_Press": "Développé épaules à la poulie",
        "Side_Lateral_Raise": "Élévations latérales",
        "Seated_Side_Lateral_Raise": "Élévations latérales assis",
        "One-Arm_Side_Laterals": "Élévation latérale un bras",
        "Cable_Seated_Lateral_Raise": "Élévations latérales à la poulie",
        "Standing_Low-Pulley_Deltoid_Raise": "Élévation latérale poulie basse",
        "Front_Dumbbell_Raise": "Élévations frontales haltères",
        "Front_Cable_Raise": "Élévation frontale à la poulie",
        "Standing_Front_Barbell_Raise_Over_Head": "Élévation frontale barre",
        "Reverse_Flyes": "Oiseau aux haltères",
        "Seated_Bent-Over_Rear_Delt_Raise": "Oiseau assis",
        "Reverse_Machine_Flyes": "Oiseau à la machine (pec deck inversé)",
        "Cable_Rear_Delt_Fly": "Oiseau à la poulie",
        "Face_Pull": "Face pull",
        "Upright_Barbell_Row": "Rowing menton barre",
        "Dumbbell_One-Arm_Upright_Row": "Rowing menton haltère",
        "External_Rotation_with_Cable": "Rotation externe à la poulie",
    },
    "pecs": {
        "Barbell_Bench_Press_-_Medium_Grip": "Développé couché",
        "Wide-Grip_Barbell_Bench_Press": "Développé couché prise large",
        "Barbell_Incline_Bench_Press_-_Medium_Grip": "Développé incliné barre",
        "Decline_Barbell_Bench_Press": "Développé décliné barre",
        "Dumbbell_Bench_Press": "Développé couché haltères",
        "Incline_Dumbbell_Press": "Développé incliné haltères",
        "Decline_Dumbbell_Bench_Press": "Développé décliné haltères",
        "Hammer_Grip_Incline_DB_Bench_Press": "Développé incliné haltères prise neutre",
        "Smith_Machine_Bench_Press": "Développé couché à la Smith",
        "Smith_Machine_Incline_Bench_Press": "Développé incliné à la Smith",
        "Machine_Bench_Press": "Développé couché à la machine",
        "Leverage_Chest_Press": "Presse pectoraux convergente",
        "Leverage_Incline_Chest_Press": "Presse incliné convergente",
        "Cable_Chest_Press": "Développé à la poulie",
        "Dumbbell_Flyes": "Écarté couché haltères",
        "Incline_Dumbbell_Flyes": "Écarté incliné haltères",
        "Butterfly": "Pec deck (butterfly)",
        "Cable_Crossover": "Écarté poulie vis-à-vis",
        "Low_Cable_Crossover": "Écarté poulie basse",
        "Incline_Cable_Flye": "Écarté poulie banc incliné",
        "Flat_Bench_Cable_Flyes": "Écarté poulie banc plat",
        "Straight-Arm_Dumbbell_Pullover": "Pull-over haltère",
        "Pushups": "Pompes",
        "Push-Up_Wide": "Pompes prise large",
        "Push-Ups_With_Feet_Elevated": "Pompes pieds surélevés",
    },
    "jambes": {
        "Barbell_Squat": "Squat barre",
        "Barbell_Full_Squat": "Squat complet",
        "Front_Squat_Clean_Grip": "Front squat",
        "Smith_Machine_Squat": "Squat à la Smith",
        "Hack_Squat": "Hack squat",
        "Dumbbell_Squat": "Squat haltères",
        "Plie_Dumbbell_Squat": "Squat sumo haltère",
        "Leg_Press": "Presse à cuisses",
        "Narrow_Stance_Leg_Press": "Presse à cuisses pieds serrés",
        "Leg_Extensions": "Leg extension",
        "Lying_Leg_Curls": "Leg curl allongé",
        "Seated_Leg_Curl": "Leg curl assis",
        "Standing_Leg_Curl": "Leg curl debout",
        "Romanian_Deadlift": "Soulevé de terre roumain",
        "Stiff-Legged_Dumbbell_Deadlift": "Soulevé de terre jambes tendues haltères",
        "Sumo_Deadlift": "Soulevé de terre sumo",
        "Dumbbell_Lunges": "Fentes haltères",
        "Barbell_Walking_Lunge": "Fentes marchées barre",
        "Split_Squat_with_Dumbbells": "Squat bulgare haltères",
        "Dumbbell_Step_Ups": "Montées sur banc haltères",
        "Barbell_Hip_Thrust": "Hip thrust",
        "Barbell_Glute_Bridge": "Pont fessier barre",
        "Thigh_Abductor": "Abducteurs à la machine",
        "Thigh_Adductor": "Adducteurs à la machine",
        "Standing_Calf_Raises": "Mollets debout à la machine",
        "Seated_Calf_Raise": "Mollets assis",
        "Calf_Press_On_The_Leg_Press_Machine": "Mollets à la presse",
        "Good_Morning": "Good morning",
    },
    "abdos": {
        "Crunches": "Crunch",
        "Ab_Crunch_Machine": "Crunch à la machine",
        "Cable_Crunch": "Crunch à la poulie",
        "Rope_Crunch": "Crunch à la corde",
        "Reverse_Crunch": "Crunch inversé",
        "Decline_Crunch": "Crunch décliné",
        "Oblique_Crunches_-_On_The_Floor": "Crunch obliques",
        "Cross-Body_Crunch": "Crunch croisé",
        "Sit-Up": "Sit-up",
        "Plank": "Gainage",
        "Side_Bridge": "Gainage latéral",
        "Russian_Twist": "Russian twist",
        "Flat_Bench_Lying_Leg_Raise": "Relevés de jambes sur banc",
        "Bent-Knee_Hip_Raise": "Relevé de bassin genoux pliés",
        "Leg_Pull-In": "Ramené de genoux au sol",
        "Seated_Leg_Tucks": "Ramené de genoux assis",
        "Barbell_Ab_Rollout": "Roulette abdos (rollout)",
        "Dead_Bug": "Dead bug",
        "Air_Bike": "Crunch vélo",
        "Standing_Cable_Wood_Chop": "Bûcheron à la poulie",
        "Pallof_Press": "Pallof press",
        "Dumbbell_Side_Bend": "Flexion latérale haltère",
        "Jackknife_Sit-Up": "Crunch en V (jackknife)",
    },
}


def download(url: str, target: str) -> bool:
    """Faux si l'animation n'existe pas dans la version gratuite."""
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=30) as response, open(target, "wb") as f:
                f.write(response.read())
            return True
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return False
            if error.code != 429:
                raise
            time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"Trop de requêtes : {url}")


def main(work: str) -> None:
    os.makedirs(work, exist_ok=True)
    source_path = os.path.join(work, "exercises.json")
    if not os.path.exists(source_path):
        urllib.request.urlretrieve(f"{SOURCE}/dist/exercises.json", source_path)
    by_id = {e["id"]: e for e in json.load(open(source_path))}
    media = json.load(open(os.path.join(ROOT, "scripts", "exercisedb_media.json")))

    stills = os.path.join(OUT, "images")
    anims = os.path.join(OUT, "anim")
    os.makedirs(stills, exist_ok=True)
    os.makedirs(anims, exist_ok=True)
    catalog = []
    missing = []
    for group, names in SELECTION.items():
        for order, (ex_id, name) in enumerate(names.items()):
            source = by_id[ex_id]
            catalog.append({
                "id": ex_id,
                "name": name,
                "group": group,
                "equipment": source["equipment"],
                "isBodyweight": source["equipment"] == "body only",
                "order": order,
            })
            gif = os.path.join(anims, f"{ex_id}.gif")
            if not os.path.exists(gif):
                ok = download(f"{MEDIA}/{media[ex_id]}.gif", gif)
                time.sleep(0.5)
                if not ok:
                    missing.append(ex_id)
                    continue
            still = os.path.join(stills, f"{ex_id}.jpg")
            if not os.path.exists(still):
                # Première image de l'animation : la position de départ, pour les vignettes.
                subprocess.run(
                    ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "85", gif, "--out", still],
                    check=True, capture_output=True,
                )

    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=1)
    print(f"{len(catalog)} exos écrits dans {OUT}")
    if missing:
        print("Sans animation (à remplacer dans exercisedb_media.json) :", ", ".join(missing))


if __name__ == "__main__":
    main(sys.argv[1])
