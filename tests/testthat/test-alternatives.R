test_that("all recorded alternatives preserve baseline and match verified count changes", {
  expected <- list(
    jamshid_sisters_reading = c(0, -2),
    bahman_tabari_daughters = c(0, 2),
    gudarz_named_sons = c(-70, 0),
    katayun_farshidvard_reading = c(0, 0),
    tataka_valmiki_birth_episode = c(-1, 0),
    vibhishana_valmiki_daughter = c(0, 0),
    vishwamitra_bhagavata_household = c(-3, 0),
    kesari_brahmanda_five = c(4, 0),
    benjamin_numbers_clans = c(-5, 0),
    simeon_numbers_clans = c(-1, 0),
    asher_numbers_clans = c(-1, 0),
    david_samuel_jerusalem = c(-2, 0),
    saul_samuel_roster = c(-1, 0),
    basil_macrina_nine = c(-1, 0),
    galla_smith_merged_child = c(-1, 0),
    draupadi_adi_95_names = c(0, 0),
    bharata_sunanda_genealogy = c(-9, 0),
    pururavas_bhagavata_names = c(0, 0),
    jamadagni_adi_four = c(-1, 0),
    vasudeva_bhagavata_rosters = c(3, 1),
    bhrigu_mani_seven = c(5, 0),
    aniruddha_wilson_mother = c(0, 0),
    drupada_vyasa_eleven = c(1, 0),
    shukra_devayani_urjasvati = c(0, 0),
    shukra_adi_four_names = c(0, 0),
    constantine_ii_mother_unassigned = c(0, 0),
    begil_literal_plural_minimum = c(1, 2),
    ushun_formulaic_daughter = c(0, -1),
    cuchulainn_human_parentage = c(0, 0),
    mahavira_digambara_celibacy = c(0, -1),
    arthur_geoffrey_genealogy = c(0, 1),
    vulcan_cicero_jupiter = c(0, 0),
    aeneas_livy_lavinia = c(0, 0),
    numa_lucretia_pompilia = c(0, 0),
    numa_four_sons = c(4, 0),
    nut_plutarch_epagomenal = c(1, 0),
    enki_namma_maternal_account = c(0, 0),
    enbilulu_enki_damgalnunna = c(0, 0),
    louhi_two_daughters_scope = c(-1, 0),
    bragi_edda_mother_unassigned = c(0, 0),
    sigyn_guerber_two = c(0, 0),
    thor_guerber_family = c(1, 0),
    bodb_gregory_dagda = c(0, 0),
    ji_chang_shiji_tai_si_ten = c(-90, 0),
    manasa_shiva_lotus = c(0, 0),
    mary_catholic_kinship = c(-4, -2),
    ukehi_ritual_performer = c(0, 0),
    mandodari_mani_three = c(0, 0),
    hamza_khawla_biography = c(0, 2),
    khalid_mughultay_five = c(1, 0),
    sad_baladhuri_named_additions = c(1, 1),
    ali_irshad_27 = c(-3, -3),
    musa_irshad_english_37 = c(1, -1),
    muttalib_fatimah_tabari = c(1, -2),
    muttalib_nutaylah_ibn_sad = c(1, 0),
    hashim_salma_haq_note = c(0, -1),
    daksha_bhagavata_16 = c(0, -8),
    lot_two_daughters = c(0, -2),
    job_both_families = c(7, 3),
    shantanu_surviving_son = c(-7, 0),
    bathsheba_named_genealogy = c(-1, 0),
    jesse_eight_sons = c(1, 0),
    danu_bhagavata_61 = c(21, 0),
    vinata_mahabharata_six = c(4, 0),
    vasishtha_vishnu_names = c(0, 0),
    prahlada_mahabharata_three = c(2, 0),
    aphrodite_hesiod_two = c(-1, 0),
    atlas_apollodorus_pleiades = c(-1, -5),
    jason_apollodorus_two = c(1, 0),
    poseidon_apollodorus_rhode = c(0, 1),
    menelaus_apollodorus_nicostratus = c(1, 0),
    priam_apollodorus_ten = c(-9, 0),
    paris_dictys_three = c(3, -1),
    simhika_vishnu_parentage = c(0, 0)
  )
  baseline <- repository$children
  before <- baseline
  base <- summarize_counts(baseline)
  expect_setequal(names(expected), vapply(repository$alternatives, `[[`, character(1), "id"))
  for (a in repository$alternatives) {
    changed <- apply_alternative(baseline, a)
    result <- summarize_counts(changed)
    expect_equal(nrow(changed), nrow(baseline), info = a$id)
    expect_equal(c(result$sons - base$sons, result$daughters - base$daughters), expected[[a$id]], info = a$id)
    targets <- vapply(a$changes, function(c) paste(c$epic, c$parent, sep = "\r"), character(1))
    unaffected <- baseline[!row_key(baseline) %in% targets, ]
    actual <- changed[match(row_key(unaffected), row_key(changed)), ]
    rownames(actual) <- rownames(unaffected) <- NULL
    expect_identical(actual, unaffected, info = a$id)
  }
  expect_identical(baseline, before)
})
