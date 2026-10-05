import copy
import subprocess
import sys

import pytest

from scripts.analyze import (
    CHILDREN,
    POLICIES,
    PRAYERS,
    ROOT,
    apply_alternative,
    generate,
    load_repository,
    number,
    read_rows,
    row_key,
    source_alternatives,
    summarize,
    validate_rows,
)


@pytest.fixture(scope="module")
def repository():
    return load_repository()


def record(rows, parent):
    return next(row for row in rows if row_key(row)[1] == parent)


def test_source_corrections(repository):
    current, _ = repository
    rows = current[CHILDREN]
    herod = record(rows, "Herod and Malthace")
    assert (herod["n_daughters"], herod["daughters"]) == ("1", "Olympias")
    hannah = record(rows, "Elkanah and Hannah")
    assert (hannah["n_sons"], hannah["n_daughters"]) == ("4", "2")
    hosea = record(rows, "Hosea and Gomer")
    assert (hosea["n_sons"], hosea["n_unknown_sex"]) == ("2", "0")
    assert record(current[PRAYERS], "Hannah")["sons_born"] == "1"
    assert record(current[PRAYERS], "Zechariah and Elizabeth")["epic"] == "christian_nt"
    levi = record(rows, "Levi and wife (unnamed)")
    assert (levi["n_daughters"], levi["daughters"]) == ("1", "Jochebed")
    ravana = record(rows, "Ravana and Mandodari")
    assert (ravana["n_sons"], ravana["n_daughters"]) == ("1", "0")
    malavi = record(rows, "Ashvapati and Malavi")
    assert (malavi["n_sons"], malavi["daughters"]) == ("100", "Savitri")
    assert not any(r["parents"] == "Sagara and Malavi" for r in rows)


def test_ravana_alternative_moves_children_without_duplication(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == "mandodari_mani_three")
    changed = apply_alternative(baseline, alternative)
    for rows, atikaya_mother, aksha_mother in (
        (baseline, "Dhanyamalini", "unknown"),
        (changed, "Mandodari", "Mandodari"),
    ):
        family = [r for r in rows if r["husband_id"] == "ramayan::ravana"]
        sons = [child for r in family for child in r["sons"].split("; ") if child]
        assert len(sons) == len(set(sons)) == 6
        assert summarize(family)["sons"] == 6
        for child, mother in (
            ("Atikaya", atikaya_mother),
            ("Aksha (Akshayakumara)", aksha_mother),
        ):
            assert [r["wife"] for r in family if child in r["sons"].split("; ")] == [
                mother
            ]


def test_constantine_maternity_alternative_preserves_all_children(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(
        a for a in alternatives if a["id"] == "constantine_ii_mother_unassigned"
    )
    changed = apply_alternative(baseline, alternative)
    father_id = record(baseline, "Constantine and Fausta")["husband_id"]
    for rows, mother in ((baseline, "Fausta"), (changed, "unknown")):
        family = [r for r in rows if r["husband_id"] == father_id]
        assert summarize(family)["sons"] == 4
        assert summarize(family)["daughters"] == 2
        assert [r["wife"] for r in family if "Constantine II" in r["sons"]] == [mother]
        assert record(family, "Constantine and Minervina")["sons"] == "Crispus"


def test_mother_split_conserves_children(repository):
    current, _ = repository
    suniti = record(current[CHILDREN], "Uttanapada and Suniti")
    suruchi = record(current[CHILDREN], "Uttanapada and Suruchi")
    assert suniti["sons"] == "Dhruva"
    assert suruchi["sons"] == "Uttama"
    assert number(suniti, "n_sons") + number(suruchi, "n_sons") == 2


def test_kinship_repairs_do_not_keep_sibling_or_stepmother_as_parent(repository):
    rows = repository[0][CHILDREN]
    gyatsa = [r for r in rows if "Gyatsa" in r["sons"]]
    assert len(gyatsa) == 1
    assert gyatsa[0]["husband"] == "Senglon Gyalpo"
    assert gyatsa[0]["wife"] == "unknown"
    gesar = record(rows, "Senglon Gyalpo and Lhakar Dronma")
    assert gesar["sons"] == "Gesar (Chori)"
    siyavash = [r for r in rows if r["sons"] == "Siyavash"]
    assert len(siyavash) == 1
    assert siyavash[0]["husband"] == "Kay Kavus"
    assert siyavash[0]["wife"] == "unknown"
    assert not any(
        r["parents"] in {"Gesar and Brugmo (Sechan Dugmo)", "Kay Kavus and Sudabeh"}
        for r in rows
    )


@pytest.mark.parametrize(
    "alternative_id,child,field,before,after",
    [
        (
            "manasa_shiva_lotus",
            "Manasa",
            "daughters",
            "Kashyapa (mind-born Manasa)",
            "Shiva (other origins)",
        ),
        (
            "bodb_gregory_dagda",
            "Bodb Derg (Bodb of Femen)",
            "sons",
            "Eochu Gab and mother of Bodb (unnamed)",
            "Dagda (other children; mothers unassigned)",
        ),
        (
            "enki_namma_maternal_account",
            "Enki",
            "sons",
            "Anu (Enlil and Enki; mothers unassigned)",
            "Namma (Enki maternal account)",
        ),
        (
            "enbilulu_enki_damgalnunna",
            "Enbilulu",
            "sons",
            "Enlil and Ninlil",
            "Enki and Damgalnunna (Enbilulu account)",
        ),
    ],
)
def test_linked_origins_move_each_child_once(
    repository, alternative_id, child, field, before, after
):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == alternative_id)
    changed = apply_alternative(baseline, alternative)
    for rows, parent in ((baseline, before), (changed, after)):
        matches = [r["parents"] for r in rows if child in r[field].split("; ")]
        assert matches == [parent]


def test_ukehi_units_preserve_eight_offspring_without_a_couple(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == "ukehi_ritual_performer")
    changed = apply_alternative(baseline, alternative)
    for rows, counts in ((baseline, (5, 0)), (changed, (0, 3))):
        amaterasu = record(rows, "Amaterasu (ukehi claimed offspring)")
        susanoo = record(rows, "Susanoo (ukehi claimed offspring)")
        assert amaterasu["husband"] == "none"
        assert amaterasu["wife"] == "Amaterasu"
        assert amaterasu["row_type"] == susanoo["row_type"] == "single_divine"
        assert (number(amaterasu, "n_sons"), number(amaterasu, "n_daughters")) == counts
        assert summarize([amaterasu, susanoo])["sons"] == 5
        assert summarize([amaterasu, susanoo])["daughters"] == 3


def test_fengshen_family_scope_and_maternal_repair(repository):
    rows = repository[0][CHILDREN]
    wen = record(rows, "Ji Chang (Fengshen Yanyi family account)")
    assert (wen["n_sons"], wen["alternate_n_sons"]) == ("100", "10")
    assert wen["row_type"] == "multi_wife_agg"
    assert wen["wife"] == "multiple"
    assert wen["sons"].count("Lei Zhenzi") == 1
    zhou = record(rows, "King Zhou and Queen Jiang")
    assert zhou["sons"] == "Yin Jiao, Yin Hong"
    assert not any(r["parents"] == "King Zhou and Daji" for r in rows)


@pytest.mark.parametrize(
    "alternative_id,father,child,before,after",
    [
        ("bragi_edda_mother_unassigned", "Odin", "Bragi", "Gunnlod", "unknown"),
        ("sigyn_guerber_two", "Loki", "Vali", "unknown", "Sigyn"),
        ("thor_guerber_family", "Thor", "Modi", "unknown", "Jarnsaxa"),
    ],
)
def test_norse_alternatives_move_children_once(
    repository, alternative_id, father, child, before, after
):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == alternative_id)
    changed = apply_alternative(baseline, alternative)
    for rows, mother in ((baseline, before), (changed, after)):
        matches = [
            r
            for r in rows
            if r["epic"] == "norse"
            and r["husband"] == father
            and child in r["sons"].split("; ")
        ]
        assert [r["wife"] for r in matches] == [mother]


def test_norse_maternal_attributions_and_stepfather(repository):
    rows = repository[0][CHILDREN]
    assert record(rows, "Odin and Frigg")["sons"] == "Baldr"
    assert record(rows, "Thor and Sif")["n_sons"] == "0"
    ullr = record(rows, "Sif and father of Ullr (unnamed)")
    assert (ullr["sons"], ullr["husband"], ullr["wife"]) == ("Ullr", "unknown", "Sif")
    njord = record(rows, "Njord and his unnamed sister")
    assert (njord["n_sons"], njord["n_daughters"], njord["wife_id"]) == ("1", "1", "")
    assert not any(r["parents"] == "Njord and Skadi" for r in rows)


def test_kojiki_direct_births_do_not_count_grandchildren(repository):
    row = record(repository[0][CHILDREN], "Izanagi and Izanami (direct deity births)")
    assert (
        number(row, "n_sons"),
        number(row, "n_daughters"),
        number(row, "n_unknown_sex"),
    ) == (12, 4, 2)
    assert len(row["sons"].split("; ")) == 12
    assert len(row["daughters"].split("; ")) == 4
    assert "Hayaakitsuhime" in row["daughters"]
    assert "Ogetsuhime" in row["daughters"]
    assert "Foam-Calm" not in row["sons"] + row["daughters"]
    assert "Great-Vale-Princess" not in row["daughters"]


def test_louhi_alternative_keeps_both_daughters(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(
        a for a in alternatives if a["id"] == "louhi_two_daughters_scope"
    )
    changed = apply_alternative(baseline, alternative)
    name = "Louhi (children in Runo 38; father unassigned)"
    assert record(baseline, name)["n_sons"] == "1"
    assert record(changed, name)["n_sons"] == "0"
    assert record(baseline, name)["n_daughters"] == "2"
    assert record(changed, name)["daughters"] == record(baseline, name)["daughters"]


def test_quraysh_maternal_assignments_do_not_duplicate_moved_children(repository):
    rows = repository[0][CHILDREN]
    families = [r for r in rows if r["husband"] == "Abu Sufyan"]
    assert len(families) == 3
    for child, field, mother in (
        ("Yazid", "sons", "Zaynab bint Nawfal"),
        ("Umm Habibah (Ramla)", "daughters", "Safiyyah bint Abi al-As"),
        ("Muawiya", "sons", "Hind bint Utbah"),
    ):
        matches = [r for r in families if child in r[field].split("; ")]
        assert [r["wife"] for r in matches] == [mother]
    assert (summarize(families)["sons"], summarize(families)["daughters"]) == (4, 4)
    awf = [r for r in rows if r["husband"] == "Abd al-Rahman ibn Awf"]
    assert len(awf) == 4
    sons = [child for r in awf for child in r["sons"].split("; ")]
    assert len(sons) == len(set(sons)) == 7
    assert record(awf, "Abd al-Rahman ibn Awf and Tumadur")["sons"] == (
        "Abu Salama (Abdullah al-Asghar)"
    )
    assert {r["wife"] for r in awf if "Salim" in r["sons"]} == {
        "Umm Kulthum bint Utba",
        "Sahla bint Suhayl",
    }


def test_distinct_origin_accounts_keep_each_moved_child_once(repository):
    rows = repository[0][CHILDREN]
    for child, parent in (
        ("Sukesha", "Vidyutkesha and Salakatankata"),
        ("Jalandhara", "Shiva (other origins)"),
        ("Ayyappa", "Shiva and Mohini"),
        ("Jayanti", "Indra and mother of Jayanti (unnamed)"),
    ):
        matches = [r for r in rows if child in r["sons"] or child in r["daughters"]]
        assert [r["parents"] for r in matches] == [parent]
    assert record(rows, "Indra and Shachi")["n_sons"] == "3"
    assert record(rows, "Kashyapa and Diti")["n_sons"] == "51"
    assert record(rows, "Bali (Mahabali) and Ashana")["n_sons"] == "100"


def test_hamza_alternative_moves_yala_and_keeps_other_children(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == "hamza_khawla_biography")
    changed = apply_alternative(baseline, alternative)
    for rows, mother, daughters in (
        (baseline, "daughter of al-Milla ibn Malik", 1),
        (changed, "Khawla bint Qays", 3),
    ):
        hamza = [r for r in rows if r["husband"] == "Hamza"]
        assert len(hamza) == 3
        assert [r["wife"] for r in hamza if "Ya'la" in r["sons"].split("; ")] == [
            mother
        ]
        assert summarize(hamza)["sons"] == 3
        assert summarize(hamza)["daughters"] == daughters
        assert record(hamza, "Hamza and Salma bint Umays")["daughters"] == "Umama"


def test_sad_maternal_parts_replace_the_old_subset(repository):
    rows = repository[0][CHILDREN]
    sad = [r for r in rows if r["husband"] == "Sa'd ibn Abi Waqqas"]
    assert len(sad) == 12
    assert (summarize(sad)["sons"], summarize(sad)["daughters"]) == (18, 18)
    assert not any(
        r["parents"] == "Sa'd ibn Abi Waqqas and wife (unnamed)" for r in sad
    )
    assert record(sad, "Sa'd ibn Abi Waqqas and Salma of Taghlib")["sons"] == "Abdullah"
    assert record(sad, "Sa'd ibn Abi Waqqas and Salma bint Khasafa")["sons"] == (
        "Umayr al-Asghar; Amr; Imran"
    )
    residual = record(sad, "Sa'd ibn Abi Waqqas (remaining mothers; Ibn Sa'd)")
    assert residual["daughters"] == "Amra; Aisha"
    assert residual["row_type"] == "multi_wife_agg"


def test_rehoboam_has_one_non_overlapping_aggregate(repository):
    current, _ = repository
    after = [
        r for r in current[CHILDREN] if r["husband_id"] == "hebrew_bible::rehoboam"
    ]
    assert len(after) == 1
    assert after[0]["row_type"] == "multi_wife_agg"
    assert summarize(after)["sons"] == 28
    assert summarize(after)["daughters"] == 60
    assert summarize(after, "direct_parent_rows")["rows"] == 0


def test_alternatives_replace_without_mutating_baseline(repository):
    current, alternatives = repository
    baseline = copy.deepcopy(current[CHILDREN])
    expected = {
        "jamshid_sisters_reading": (0, -2),
        "bahman_tabari_daughters": (0, 2),
        "gudarz_named_sons": (-70, 0),
        "katayun_farshidvard_reading": (0, 0),
        "tataka_valmiki_birth_episode": (-1, 0),
        "vibhishana_valmiki_daughter": (0, 0),
        "vishwamitra_bhagavata_household": (-3, 0),
        "kesari_brahmanda_five": (4, 0),
        "benjamin_numbers_clans": (-5, 0),
        "simeon_numbers_clans": (-1, 0),
        "asher_numbers_clans": (-1, 0),
        "david_samuel_jerusalem": (-2, 0),
        "saul_samuel_roster": (-1, 0),
        "basil_macrina_nine": (-1, 0),
        "galla_smith_merged_child": (-1, 0),
        "draupadi_adi_95_names": (0, 0),
        "bharata_sunanda_genealogy": (-9, 0),
        "pururavas_bhagavata_names": (0, 0),
        "jamadagni_adi_four": (-1, 0),
        "vasudeva_bhagavata_rosters": (3, 1),
        "bhrigu_mani_seven": (5, 0),
        "aniruddha_wilson_mother": (0, 0),
        "drupada_vyasa_eleven": (1, 0),
        "shukra_devayani_urjasvati": (0, 0),
        "shukra_adi_four_names": (0, 0),
        "constantine_ii_mother_unassigned": (0, 0),
        "begil_literal_plural_minimum": (1, 2),
        "ushun_formulaic_daughter": (0, -1),
        "cuchulainn_human_parentage": (0, 0),
        "mahavira_digambara_celibacy": (0, -1),
        "arthur_geoffrey_genealogy": (0, 1),
        "vulcan_cicero_jupiter": (0, 0),
        "aeneas_livy_lavinia": (0, 0),
        "numa_lucretia_pompilia": (0, 0),
        "numa_four_sons": (4, 0),
        "nut_plutarch_epagomenal": (1, 0),
        "enki_namma_maternal_account": (0, 0),
        "enbilulu_enki_damgalnunna": (0, 0),
        "louhi_two_daughters_scope": (-1, 0),
        "bragi_edda_mother_unassigned": (0, 0),
        "sigyn_guerber_two": (0, 0),
        "thor_guerber_family": (1, 0),
        "bodb_gregory_dagda": (0, 0),
        "ji_chang_shiji_tai_si_ten": (-90, 0),
        "manasa_shiva_lotus": (0, 0),
        "mary_catholic_kinship": (-4, -2),
        "ukehi_ritual_performer": (0, 0),
        "mandodari_mani_three": (0, 0),
        "hamza_khawla_biography": (0, 2),
        "khalid_mughultay_five": (1, 0),
        "sad_baladhuri_named_additions": (1, 1),
        "ali_irshad_27": (-3, -3),
        "musa_irshad_english_37": (1, -1),
        "muttalib_fatimah_tabari": (1, -2),
        "muttalib_nutaylah_ibn_sad": (1, 0),
        "hashim_salma_haq_note": (0, -1),
        "daksha_bhagavata_16": (0, -8),
        "lot_two_daughters": (0, -2),
        "job_both_families": (7, 3),
        "shantanu_surviving_son": (-7, 0),
        "bathsheba_named_genealogy": (-1, 0),
        "jesse_eight_sons": (1, 0),
        "danu_bhagavata_61": (21, 0),
        "vinata_mahabharata_six": (4, 0),
        "vasishtha_vishnu_names": (0, 0),
        "prahlada_mahabharata_three": (2, 0),
        "aphrodite_hesiod_two": (-1, 0),
        "atlas_apollodorus_pleiades": (-1, -5),
        "jason_apollodorus_two": (1, 0),
        "poseidon_apollodorus_rhode": (0, 1),
        "menelaus_apollodorus_nicostratus": (1, 0),
        "priam_apollodorus_ten": (-9, 0),
        "paris_dictys_three": (3, -1),
        "simhika_vishnu_parentage": (0, 0),
    }
    base = summarize(baseline)
    for alternative in alternatives:
        changed = apply_alternative(baseline, alternative)
        assert len(changed) == len(baseline)
        result = summarize(changed)
        sons_delta, daughters_delta = expected[alternative["id"]]
        assert result["sons"] - base["sons"] == sons_delta
        assert result["daughters"] - base["daughters"] == daughters_delta
    assert current[CHILDREN] == baseline


def test_source_columns_drive_alternative_counts(repository):
    rows = copy.deepcopy(repository[0][CHILDREN])
    jesse = record(rows, "Jesse and wife (unnamed)")
    assert (jesse["n_sons"], jesse["alternate_n_sons"]) == ("7", "8")
    assert jesse["alternate_n_daughters"] == "2"
    alternatives = source_alternatives(rows)
    assert {a["id"] for a in alternatives} == {
        "jamshid_sisters_reading",
        "bahman_tabari_daughters",
        "gudarz_named_sons",
        "katayun_farshidvard_reading",
        "tataka_valmiki_birth_episode",
        "vibhishana_valmiki_daughter",
        "vishwamitra_bhagavata_household",
        "kesari_brahmanda_five",
        "benjamin_numbers_clans",
        "simeon_numbers_clans",
        "asher_numbers_clans",
        "david_samuel_jerusalem",
        "saul_samuel_roster",
        "basil_macrina_nine",
        "galla_smith_merged_child",
        "draupadi_adi_95_names",
        "bharata_sunanda_genealogy",
        "pururavas_bhagavata_names",
        "jamadagni_adi_four",
        "vasudeva_bhagavata_rosters",
        "bhrigu_mani_seven",
        "aniruddha_wilson_mother",
        "drupada_vyasa_eleven",
        "shukra_devayani_urjasvati",
        "shukra_adi_four_names",
        "constantine_ii_mother_unassigned",
        "begil_literal_plural_minimum",
        "ushun_formulaic_daughter",
        "cuchulainn_human_parentage",
        "mahavira_digambara_celibacy",
        "arthur_geoffrey_genealogy",
        "vulcan_cicero_jupiter",
        "aeneas_livy_lavinia",
        "numa_lucretia_pompilia",
        "numa_four_sons",
        "nut_plutarch_epagomenal",
        "enki_namma_maternal_account",
        "enbilulu_enki_damgalnunna",
        "louhi_two_daughters_scope",
        "bragi_edda_mother_unassigned",
        "sigyn_guerber_two",
        "thor_guerber_family",
        "bodb_gregory_dagda",
        "ji_chang_shiji_tai_si_ten",
        "manasa_shiva_lotus",
        "mary_catholic_kinship",
        "ukehi_ritual_performer",
        "mandodari_mani_three",
        "hamza_khawla_biography",
        "khalid_mughultay_five",
        "sad_baladhuri_named_additions",
        "ali_irshad_27",
        "musa_irshad_english_37",
        "muttalib_fatimah_tabari",
        "muttalib_nutaylah_ibn_sad",
        "hashim_salma_haq_note",
        "daksha_bhagavata_16",
        "jesse_eight_sons",
        "danu_bhagavata_61",
        "vinata_mahabharata_six",
        "vasishtha_vishnu_names",
        "prahlada_mahabharata_three",
        "aphrodite_hesiod_two",
        "atlas_apollodorus_pleiades",
        "jason_apollodorus_two",
        "poseidon_apollodorus_rhode",
        "menelaus_apollodorus_nicostratus",
        "priam_apollodorus_ten",
        "paris_dictys_three",
        "simhika_vishnu_parentage",
    }
    jesse["alternate_n_sons"] = "9"
    jesse["alternate_sons"] = "nine sons in a synthetic test account"
    alternative = next(
        a for a in source_alternatives(rows) if a["id"] == "jesse_eight_sons"
    )
    changed = apply_alternative(rows, alternative)
    assert summarize(changed)["sons"] - summarize(rows)["sons"] == 2
    assert jesse["n_sons"] == "7"


@pytest.mark.parametrize(
    "field,value",
    [
        ("alternate_id", ""),
        ("alternate_source", ""),
        ("alternate_comments", ""),
        ("alternate_n_sons", ""),
        ("alternate_n_sons", "-1"),
        ("alternate_n_sons", "nan"),
        ("alternate_n_sons", "1.5"),
        ("alternate_sons", ""),
    ],
)
def test_incomplete_or_invalid_source_alternatives_fail(repository, field, value):
    row = dict(record(repository[0][CHILDREN], "Jesse and wife (unnamed)"))
    row[field] = value
    with pytest.raises(ValueError):
        validate_rows([row], CHILDREN)


@pytest.mark.parametrize(
    "husband,sons,daughters",
    [
        ("Hasan ibn Ali", 8, 7),
        ("Husayn ibn Ali", 4, 2),
        ("Ja'far al-Sadiq", 7, 3),
        ("Ali Zayn al-Abidin", 11, 4),
        ("Muhammad al-Baqir", 5, 2),
        ("Muhammad al-Jawad", 2, 2),
        ("Ali al-Hadi", 4, 1),
        ("Musa al-Kadhim", 18, 19),
    ],
)
def test_irshad_maternal_parts_reconcile(repository, husband, sons, daughters):
    rows = [r for r in repository[0][CHILDREN] if r["husband"] == husband]
    total = summarize(rows)
    assert (total["sons"], total["daughters"]) == (sons, daughters)


def test_imam_children_are_not_assigned_to_unverified_mothers(repository):
    rows = repository[0][CHILDREN]
    for parent, sons in (
        ("Ali Zayn al-Abidin and Umm Abdullah bint al-Hasan", "Muhammad al-Baqir"),
        ("Musa al-Kadhim and Umm al-Banin", "Ali al-Ridha"),
        ("Ali al-Hadi and Hadith", "Hasan al-Askari"),
    ):
        row = record(rows, parent)
        assert (row["n_sons"], row["sons"], row["n_daughters"]) == ("1", sons, "0")
    assert record(rows, "Muhammad al-Baqir and Umm Farwa")["n_daughters"] == "0"
    residual = record(rows, "Muhammad al-Baqir (remaining mothers; al-Mufid)")
    assert "Umm Salama" in residual["daughters"]


def test_musa_edition_alternative_keeps_37_children(repository):
    rows, alternatives = repository[0][CHILDREN], repository[1]
    alternative = next(a for a in alternatives if a["id"] == "musa_irshad_english_37")
    changed = apply_alternative(rows, alternative)
    family = [r for r in changed if r["husband"] == "Musa al-Kadhim"]
    total = summarize(family)
    assert (total["sons"], total["daughters"]) == (19, 18)
    residual = record(family, "Musa al-Kadhim (remaining mothers; al-Mufid)")
    assert "Hasan (entry 8)" in residual["sons"]
    assert "Hasan (entry 16)" in residual["sons"]
    assert "Kulthum" not in residual["daughters"].split("; ")
    assert "Umm Kulthum" in residual["daughters"].split("; ")


def test_quraysh_maternal_corrections_and_aliases(repository):
    rows = repository[0][CHILDREN]
    manaf = [r for r in rows if r["husband"] == "Abd Manaf"]
    assert (summarize(manaf)["sons"], summarize(manaf)["daughters"]) == (5, 6)
    assert "Nawfal" not in record(manaf, "Abd Manaf and Atikah bint Murrah")["sons"]
    assert record(manaf, "Abd Manaf and Waqidah")["sons"] == "Nawfal"
    muttalib = [r for r in rows if r["husband"] == "Abd al-Muttalib"]
    assert len(muttalib) == 5
    assert (summarize(muttalib)["sons"], summarize(muttalib)["daughters"]) == (10, 6)
    hala = record(muttalib, "Abd al-Muttalib and Hala bint Uhayb")
    assert (hala["n_sons"], hala["sons"].count("al-Ghaydaq")) == ("3", 1)
    lubaba = record(rows, "Abbas and Lubaba bint al-Harith")
    assert (lubaba["n_sons"], lubaba["n_daughters"]) == ("6", "1")
    assert "Kathir" not in lubaba["sons"]
    assert record(rows, "Abbas and Musliyah")["sons"] == "Kathir; Tammam"
    fatimah = record(rows, "Abu Talib and Fatimah bint Asad")
    assert (fatimah["n_sons"], fatimah["n_daughters"]) == ("4", "3")
    assert "Raytah (Asma)" in fatimah["daughters"]
    assert "Tulayq" not in fatimah["sons"]
    assert record(rows, "Abu Talib and Illah")["sons"] == "Tulayq"


def test_ali_accounts_reconcile_without_pooling_maternal_attributions(repository):
    current, alternatives = repository
    rows = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == "ali_irshad_27")
    assert len(alternative["changes"]) == 10
    changed = apply_alternative(rows, alternative)
    for version, expected in ((rows, (14, 19)), (changed, (11, 16))):
        family = [r for r in version if r["husband_id"] == "islam::ali"]
        assert len(family) == 10
        total = summarize(family)
        assert (total["sons"], total["daughters"]) == expected
        assert record(family, "Ali (daughters by unnamed mothers)")["n_sons"] == "0"
    assert record(rows, "Ali and Asma bint Umays")["n_sons"] == "2"
    assert record(changed, "Ali and Asma bint Umays")["sons"] == "Yahya"
    assert (
        "Muhammad the younger (Abu Bakr)"
        in record(changed, "Ali and Layla bint Mas'ud")["sons"]
    )
    assert record(changed, "Ali and Amamah bint Abi al-As")["n_sons"] == "0"


def test_separate_births_and_mothers(repository):
    rows = repository[0][CHILDREN]
    assert record(rows, "David and Bathsheba")["n_sons"] == "5"
    assert record(rows, "Shantanu and Ganga")["n_sons"] == "8"
    gideon = [r for r in rows if r["husband_id"] == "hebrew_bible::gideon"]
    assert len(gideon) == 2
    assert summarize(gideon)["sons"] == 71
    assert "Abimelech" not in record(gideon, "Gideon (many wives)")["sons"]
    assert record(rows, "Husayn ibn Ali and Rabab")["daughters"] == "Sukayna"
    ramlah = record(rows, "Uthman and Ramlah bint Shaybah")
    fatimah = record(rows, "Uthman and Fatimah bint al-Walid")
    assert (ramlah["n_sons"], ramlah["n_daughters"]) == ("0", "3")
    assert (fatimah["n_sons"], fatimah["n_daughters"]) == ("2", "1")
    assert "Umm Sa'id" not in fatimah["sons"]


def test_requests_are_not_inferred_from_birth_outcomes(repository):
    rows = repository[0][PRAYERS]
    for parent in (
        "Zechariah and Elizabeth",
        "Abraham and Hagar",
        "Abraham and Sarah",
        "Manoah and wife",
        "Ibrahim (2nd)",
        "Parvati",
    ):
        row = record(rows, parent)
        assert row["sons_born"] == "1"
        assert row["desired_gender"] == "unspecified"
    assert record(rows, "Gandhari")["desired_gender"] == "son_and_daughter"
    assert record(rows, "Drupad")["desired_gender"] == "son"


def test_missing_alternative_target_is_rejected(repository):
    current, alternatives = repository
    alternative = copy.deepcopy(alternatives[0])
    alternative["changes"][0]["parent"] = "nonexistent family"
    with pytest.raises(ValueError, match="Alternative target"):
        apply_alternative(current[CHILDREN], alternative)


def test_linked_parentage_changes_move_rather_than_duplicate_child(repository):
    rows, alternatives = repository[0][CHILDREN], repository[1]
    alternative = next(a for a in alternatives if a["id"] == "simhika_vishnu_parentage")
    assert len(alternative["changes"]) == 2
    changed = apply_alternative(rows, alternative)
    assert record(rows, "Hiranyakashipu and Kayadhu")["daughters"] == "Simhika"
    assert record(rows, "Kashyapa and Diti")["n_daughters"] == "0"
    assert record(changed, "Hiranyakashipu and Kayadhu")["n_daughters"] == "0"
    assert record(changed, "Kashyapa and Diti")["daughters"] == "Simhika"
    assert summarize(changed) == summarize(rows)


def test_linked_alternative_rejects_missing_and_repeated_targets(repository):
    rows, alternatives = repository[0][CHILDREN], repository[1]
    original = next(a for a in alternatives if len(a["changes"]) > 1)
    for invalid in ("missing", "duplicate"):
        alternative = copy.deepcopy(original)
        if invalid == "missing":
            alternative["changes"][1]["parent"] = "nonexistent family"
        else:
            alternative["changes"].append(alternative["changes"][0])
        before = copy.deepcopy(rows)
        with pytest.raises(ValueError, match="Alternative target"):
            apply_alternative(rows, alternative)
        assert rows == before


@pytest.mark.parametrize("value", ["", "nan", "inf", "-1", "0.5"])
def test_invalid_current_counts_fail(value, repository):
    current, _ = repository
    rows = [dict(current[CHILDREN][0], n_sons=value)]
    with pytest.raises(ValueError):
        validate_rows(rows, CHILDREN)


def test_policy_math_on_known_example(repository):
    template = repository[0][CHILDREN][0]
    rows = [
        dict(
            template,
            parents="huge",
            n_sons="1000",
            n_daughters="500",
            row_type="mythical_count",
        ),
        dict(
            template,
            parents="retelling",
            n_sons="2",
            n_daughters="1",
            row_type="cross_tradition",
        ),
        dict(
            template,
            parents="ordinary",
            n_sons="3",
            n_daughters="3",
            n_unknown_sex="2",
            row_type="couple",
        ),
    ]
    assert summarize(rows)["sons"] == 1005
    assert summarize(rows, "sons_cap_200")["sons"] == 205
    assert summarize(rows, "sons_cap_200")["daughters"] == 504
    assert summarize(rows, "exclude_mythical")["rows"] == 2
    result = summarize(rows, "exclude_mythical_and_cross")
    assert result["male_pct"] == 50
    assert result["unknown_sex"] == 2
    assert summarize([], "uncapped")["male_pct"] is None
    with pytest.raises(ValueError, match="Unknown policy"):
        summarize(rows, "typo")


def test_generated_results_reconcile_and_are_current(tmp_path, repository):
    summary = generate(ROOT, tmp_path, figures=None)
    assert len(summary) == (1 + len(repository[1])) * len(POLICIES)
    groups = read_rows(tmp_path / "group_summary.csv")
    for policy in POLICIES:
        overall = next(
            r for r in summary if r["version"] == "current" and r["policy"] == policy
        )
        for column in ("epic", "historicity", "row_type"):
            parts = [
                r for r in groups if r["policy"] == policy and r["group_by"] == column
            ]
            for field in ("rows", "sons", "daughters", "unknown_sex"):
                assert sum(float(r[field]) for r in parts) == overall[field]
    for path in tmp_path.rglob("*"):
        if path.is_file():
            assert (
                path.read_bytes()
                == (ROOT / "results" / path.relative_to(tmp_path)).read_bytes()
            )


def test_cli_works_outside_repository(tmp_path):
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/analyze.py"), "--check"],
        cwd=tmp_path,
        text=True,
        capture_output=True,
        check=True,
    )
    assert "Validated" in result.stdout


def test_egyptian_parentage_and_linked_birth_account(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    anubis = [r for r in baseline if r["epic"] == "egyptian" and r["sons"] == "Anubis"]
    assert [(r["husband"], r["wife"]) for r in anubis] == [("Osiris", "Nephthys")]
    four_sons = record(baseline, "Horus and Isis (four sons)")
    assert (four_sons["wife_id"], four_sons["n_sons"]) == ("egyptian::isis", "4")
    alternative = next(a for a in alternatives if a["id"] == "nut_plutarch_epagomenal")
    changed = apply_alternative(baseline, alternative)
    for rows, expected in ((baseline, (2, 2)), (changed, (3, 2))):
        nut = [r for r in rows if r["wife_id"] == "egyptian::nut"]
        result = summarize(nut)
        assert (result["sons"], result["daughters"]) == expected
        children = [
            child
            for r in nut
            for field in ("sons", "daughters")
            for child in r[field].split("; ")
            if child
        ]
        assert len(children) == len(set(children)) == sum(expected)
    assert (
        record(changed, "Sun and Nut (Rhea; Plutarch)")["sons"]
        == "Osiris; Arueris (elder Horus)"
    )
    assert record(changed, "Hermes and Nut (Rhea; Plutarch)")["daughters"] == "Isis"
    assert record(changed, "Geb and Nut")["sons"] == "Set (Typhon)"


@pytest.mark.parametrize(
    "alternative_id,child,baseline_parent,alternate_parent",
    [
        (
            "vulcan_cicero_jupiter",
            "Vulcan",
            "Juno (Vulcan without a father)",
            "Jupiter and Juno",
        ),
        (
            "aeneas_livy_lavinia",
            "Silvius",
            "Aeneas and Lavinia",
            "Ascanius and mother of Silvius (unnamed)",
        ),
        (
            "aeneas_livy_lavinia",
            "Ascanius (Iulus)",
            "Aeneas and Creusa",
            "Aeneas and Lavinia",
        ),
        (
            "numa_lucretia_pompilia",
            "Pompilia",
            "Numa Pompilius and Tatia",
            "Numa Pompilius and Lucretia",
        ),
    ],
)
def test_roman_alternatives_move_each_child_once(
    repository, alternative_id, child, baseline_parent, alternate_parent
):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(a for a in alternatives if a["id"] == alternative_id)
    changed = apply_alternative(baseline, alternative)
    for rows, parent in ((baseline, baseline_parent), (changed, alternate_parent)):
        matches = [
            r["parents"]
            for r in rows
            if r["epic"] == "roman"
            and child in (r["sons"] + "; " + r["daughters"]).split("; ")
        ]
        assert matches == [parent]


def test_roman_corrections_preserve_source_identity(repository):
    rows = repository[0][CHILDREN]
    juno = record(rows, "Jupiter and Juno")
    assert (juno["n_sons"], juno["n_daughters"]) == ("1", "2")
    assert juno["daughters"] == "Juventas (Youth); Libertas (Liberty)"
    assert record(rows, "Neptune and Amphitrite")["wife"] == "Amphitrite"
    assert record(rows, "Jupiter and Metis")["row_type"] == "cross_tradition"
    greek = record(rows, "Zeus and Persephone")
    roman = record(rows, "Jupiter and Proserpina (Melinoe hymn)")
    assert greek["family_id"] == roman["family_id"] == "zeus_persephone_melinoe"
    assert roman["row_type"] == "cross_tradition"
    assert summarize([roman], "exclude_mythical_and_cross")["daughters"] == 0


def test_arthurian_accounts_keep_mordred_in_one_generation(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(
        a for a in alternatives if a["id"] == "arthur_geoffrey_genealogy"
    )
    changed = apply_alternative(baseline, alternative)
    for rows, parent, daughters in (
        (baseline, "Arthur and Morgause", 0),
        (changed, "Lot and Anne (Mordred; Geoffrey)", 1),
    ):
        family = [r for r in rows if r["epic"] == "arthurian"]
        assert [r["parents"] for r in family if "Mordred" in r["sons"]] == [parent]
        totals = summarize(family)
        assert (totals["sons"], totals["daughters"]) == (3, daughters)
        assert record(family, "Lancelot and Elaine of Corbenic")["sons"] == "Galahad"
    assert record(changed, "Uther Pendragon and Igraine")["daughters"] == "Anne (Anna)"


def test_jain_family_rosters_and_celibacy_alternative(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    nabhi = record(baseline, "Nabhi and Marudevi")
    assert (nabhi["n_sons"], nabhi["n_daughters"]) == ("1", "1")
    assert nabhi["daughters"] == "Sumangala"
    siddhartha = record(baseline, "Siddhartha and Trishala")
    assert (siddhartha["n_sons"], siddhartha["n_daughters"]) == ("2", "1")
    assert "Nandivardhana" in siddhartha["sons"]
    assert siddhartha["daughters"] == "Sudarsana"
    alternative = next(
        a for a in alternatives if a["id"] == "mahavira_digambara_celibacy"
    )
    changed = apply_alternative(baseline, alternative)
    parent = "Mahavira (24th Tirthankara) and Yashoda"
    assert record(baseline, parent)["n_daughters"] == "1"
    revised = record(changed, parent)
    assert (revised["n_sons"], revised["n_daughters"], revised["n_unknown_sex"]) == (
        "0",
        "0",
        "0",
    )
    assert revised["sons"] == revised["daughters"] == ""
    assert record(changed, "Siddhartha and Trishala") == siddhartha


def test_cuchulainn_attribution_counts_one_hero(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(
        a for a in alternatives if a["id"] == "cuchulainn_human_parentage"
    )
    changed = apply_alternative(baseline, alternative)
    for rows, father in ((baseline, "Lugh"), (changed, "Sualtaim")):
        family = [r for r in rows if r["wife_id"] == "celtic::deichtine"]
        assert summarize(family)["sons"] == 1
        assert [r["husband"] for r in family if r["sons"] == "Cú Chulainn"] == [father]


def test_dede_korkut_enumerations_and_literal_scope(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    bure = record(baseline, "Kam Bure and wife (unnamed)")
    assert (bure["n_sons"], bure["n_daughters"]) == ("1", "7")
    ush = record(baseline, "Ushun Koja and wife (unnamed)")
    assert (ush["n_sons"], ush["n_daughters"]) == ("2", "1")
    alternatives = {a["id"]: a for a in alternatives}
    changed = apply_alternative(baseline, alternatives["begil_literal_plural_minimum"])
    begil = record(changed, "Begil and wife (unnamed)")
    assert (begil["n_sons"], begil["n_daughters"]) == ("2", "2")
    assert record(changed, "Kam Bure and wife (unnamed)") == bure
    changed = apply_alternative(baseline, alternatives["ushun_formulaic_daughter"])
    assert record(changed, "Ushun Koja and wife (unnamed)")["n_daughters"] == "0"
    oghuz = record(baseline, "Oghuz Khan (six sons; mothers unassigned)")
    assert oghuz["epic"] == "oguzname"
    assert oghuz["row_type"] == "multi_wife_agg"
    assert oghuz["n_sons"] == "6"


def test_shahnameh_splits_and_maternal_alternative(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    fereydun = [r for r in baseline if r["husband_id"] == "shahnameh::fereydun"]
    assert summarize(fereydun)["sons"] == 3
    assert record(fereydun, "Fereydun and Arnavaz")["sons"] == "Iraj"
    assert record(fereydun, "Fereydun and Shahrnaz")["sons"] == "Salm; Tur"
    bahman = [r for r in baseline if r["husband_id"] == "shahnameh::bahman"]
    assert summarize(bahman)["sons"] == 2
    assert [r["parents"] for r in bahman if "Darab" in r["sons"]] == [
        "Bahman and Homay"
    ]
    alternative = next(
        a for a in alternatives if a["id"] == "katayun_farshidvard_reading"
    )
    changed = apply_alternative(baseline, alternative)
    for rows, maternal_sons in (
        (baseline, "Esfandiyar, Pashotan"),
        (changed, "Esfandiyar; Farshidvard"),
    ):
        family = [r for r in rows if r["husband_id"] == "shahnameh::goshtasp"]
        assert record(family, "Goshtasp and Katayun")["sons"] == maternal_sons
        assert (summarize(family)["sons"], summarize(family)["daughters"]) == (7, 2)
        for child in ("Pashotan", "Farshidvard"):
            assert sum(child in r["sons"] for r in family) == 1


def test_unsupported_suratha_relationship_is_removed(repository):
    rows = repository[0][CHILDREN]
    assert not any(r["husband"] == "Suratha" for r in rows)
    assert record(rows, "Li Jing and Lady Yin")["n_sons"] == "3"
    amarashakti = record(rows, "King Amarashakti (three sons; mothers unassigned)")
    assert amarashakti["n_sons"] == "3"
    assert amarashakti["row_type"] == "multi_wife_agg"


def test_sundiata_roster_keeps_six_children_in_distinct_maternal_groups(repository):
    rows = repository[0][CHILDREN]
    family = [r for r in rows if r["husband_id"] == "sundiata::maghan_kon_fatta"]
    assert len(family) == 3
    assert summarize(family)["sons"] == summarize(family)["daughters"] == 3
    expected = {
        "Sassouma Berete": ("Dankaran Touman", "Nana Triban"),
        "Sogolon": ("Sundiata (Mari Djata)", "Sogolon Kolonkan; Sogolon Djamarou"),
        "Namandje Kamara": ("Manding Bory (Manding Bakary)", ""),
    }
    assert {r["wife"]: (r["sons"], r["daughters"]) for r in family} == expected


def test_vishwamitra_alternative_preserves_separate_maternal_record(repository):
    current, alternatives = repository
    baseline = current[CHILDREN]
    alternative = next(
        a for a in alternatives if a["id"] == "vishwamitra_bhagavata_household"
    )
    changed = apply_alternative(baseline, alternative)
    for rows, expected_sons in ((baseline, 105), (changed, 102)):
        family = [r for r in rows if r["husband_id"] == "ramayan::vishwamitra"]
        assert len(family) == 2
        assert summarize(family)["sons"] == expected_sons
        assert summarize(family)["daughters"] == 1
        assert [r["wife"] for r in family if r["daughters"]] == ["Menaka"]
        assert summarize(family, "exclude_mythical")["daughters"] == 1
    assert record(baseline, "Vishwamitra and Menaka") == record(
        changed, "Vishwamitra and Menaka"
    )


def test_kumbhakarna_children_are_split_without_duplication(repository):
    rows = repository[0][CHILDREN]
    family = [r for r in rows if r["husband_id"] == "ramayan::kumbhakarna"]
    assert summarize(family)["sons"] == 3
    assert {r["wife"]: r["sons"] for r in family} == {
        "Vajrajwala": "Kumbha; Nikumbha",
        "Karkati": "Bhimasura (Bhima)",
    }
    assert record(rows, "Vali and Tara")["husband_id"] == "ramayan::vali"
