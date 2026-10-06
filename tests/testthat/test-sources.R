test_that("corrected family enumerations and maternal splits reconcile", {
  rows <- repository$children
  expected <- list(
    "Herod and Malthace" = c(2, 1), "Elkanah and Hannah" = c(4, 2),
    "Uttanapada and Suniti" = c(1, 0), "Uttanapada and Suruchi" = c(1, 0),
    "Ravana and Mandodari" = c(1, 0), "Ashvapati and Malavi" = c(100, 1),
    "Nabhi and Marudevi" = c(1, 1), "Siddhartha and Trishala" = c(2, 1),
    "Kam Bure and wife (unnamed)" = c(1, 7), "Ushun Koja and wife (unnamed)" = c(2, 1),
    "Jupiter and Juno" = c(1, 2)
  )
  for (parent in names(expected)) {
    x <- record(rows, parent)
    expect_equal(c(number(x, "n_sons"), number(x, "n_daughters")), expected[[parent]], info = parent)
  }
  expect_identical(record(rows, "Herod and Malthace")$daughters, "Olympias")
  expect_identical(record(rows, "Uttanapada and Suniti")$sons, "Dhruva")
  expect_identical(record(rows, "Uttanapada and Suruchi")$sons, "Uttama")
  expect_identical(record(rows, "Ashvapati and Malavi")$daughters, "Savitri")
  expect_identical(record(rows, "Nabhi and Marudevi")$daughters, "Sumangala")
  expect_identical(record(rows, "Siddhartha and Trishala")$daughters, "Sudarsana")
  expect_identical(record(rows, "Jupiter and Juno")$daughters, "Juventas (Youth); Libertas (Liberty)")
  expect_identical(record(rows, "Neptune and Amphitrite")$wife, "Amphitrite")
  expect_false(any(rows$parents %in% c(
    "Sagara and Malavi",
    "King Zhou and Daji",
    "Gesar and Brugmo (Sechan Dugmo)",
    "Kay Kavus and Sudabeh"
  )))
  expect_false(any(rows$husband == "Suratha"))
  expect_identical(record(rows, "Senglon Gyalpo and Lhakar Dronma")$sons, "Gesar (Chori)")
  gyatsa <- rows[grepl("Gyatsa", rows$sons, fixed = TRUE), ]
  expect_equal(nrow(gyatsa), 1)
  expect_identical(gyatsa$husband, "Senglon Gyalpo")
  expect_identical(gyatsa$wife, "unknown")
  expect_identical(rows$husband[rows$sons == "Siyavash"], "Kay Kavus")
})

test_that("linked source accounts move child identities exactly once", {
  cases <- list(
    c("manasa_shiva_lotus", "Manasa", "Kashyapa (mind-born Manasa)", "Shiva (other origins)", ""),
    c(
      "bodb_gregory_dagda", "Bodb Derg (Bodb of Femen)",
      "Eochu Gab and mother of Bodb (unnamed)", "Dagda (other children; mothers unassigned)", ""
    ),
    c(
      "enki_namma_maternal_account", "Enki",
      "Anu (Enlil and Enki; mothers unassigned)", "Namma (Enki maternal account)", ""
    ),
    c("enbilulu_enki_damgalnunna", "Enbilulu", "Enlil and Ninlil", "Enki and Damgalnunna (Enbilulu account)", ""),
    c("aeneas_livy_lavinia", "Ascanius (Iulus)", "Aeneas and Creusa", "Aeneas and Lavinia", "roman"),
    c("numa_lucretia_pompilia", "Pompilia", "Numa Pompilius and Tatia", "Numa Pompilius and Lucretia", "roman")
  )
  for (case in cases) {
    versions <- list(repository$children, variant(case[1]))
    for (i in 1:2) {
      rows <- versions[[i]]
      if (nzchar(case[5])) rows <- rows[rows$epic == case[5], ]
      matches <- vapply(
        strsplit(paste(rows$sons, rows$daughters, sep = "; "), "; ", fixed = TRUE),
        function(x) case[2] %in% x,
        logical(1)
      )
      expect_identical(rows$parents[matches], case[i + 2L], info = case[1])
    }
  }
  for (case in list(
    c("bragi_edda_mother_unassigned", "Odin", "Bragi", "Gunnlod", "unknown"),
    c("sigyn_guerber_two", "Loki", "Vali", "unknown", "Sigyn"),
    c("thor_guerber_family", "Thor", "Modi", "unknown", "Jarnsaxa")
  )) {
    versions <- list(repository$children, variant(case[1]))
    for (i in 1:2) {
      rows <- versions[[i]]
      rows <- rows[rows$epic == "norse" & rows$husband == case[2], ]
      matches <- vapply(strsplit(rows$sons, "; ", fixed = TRUE), function(x) case[3] %in% x, logical(1))
      expect_identical(rows$wife[matches], case[i + 3L], info = case[1])
    }
  }
})

test_that("maternal account totals retain their separate source scope", {
  expected <- list(
    "Hasan ibn Ali" = c(8, 7), "Husayn ibn Ali" = c(4, 2), "Ja'far al-Sadiq" = c(7, 3),
    "Ali Zayn al-Abidin" = c(11, 4), "Muhammad al-Baqir" = c(5, 2), "Muhammad al-Jawad" = c(2, 2),
    "Ali al-Hadi" = c(4, 1), "Musa al-Kadhim" = c(18, 19)
  )
  rows <- repository$children
  for (father in names(expected)) {
    x <- summarize_counts(rows[rows$husband == father, ])
    expect_equal(c(x$sons, x$daughters), expected[[father]], info = father)
  }
  changed <- variant("musa_irshad_english_37")
  x <- summarize_counts(changed[changed$husband == "Musa al-Kadhim", ])
  expect_equal(c(x$sons, x$daughters), c(19, 18))
  residual <- record(changed, "Musa al-Kadhim (remaining mothers; al-Mufid)")
  expect_match(residual$sons, "Hasan (entry 8)", fixed = TRUE)
  expect_match(residual$sons, "Hasan (entry 16)", fixed = TRUE)
  for (version in list(rows, variant("ali_irshad_27"))) {
    family <- version[version$husband_id == "islam::ali", ]
    expect_equal(nrow(family), 10)
  }
  a <- summarize_counts(rows[rows$husband_id == "islam::ali", ])
  b <- variant("ali_irshad_27")
  b <- summarize_counts(b[b$husband_id == "islam::ali", ])
  expect_equal(c(a$sons, a$daughters), c(14, 19))
  expect_equal(c(b$sons, b$daughters), c(11, 16))
})

test_that("aggregate and birth-scope repairs avoid overlapping family totals", {
  rows <- repository$children
  family <- rows[rows$husband_id == "hebrew_bible::rehoboam", ]
  expect_equal(nrow(family), 1)
  expect_identical(family$row_type, "multi_wife_agg")
  expect_equal(c(summarize_counts(family)$sons, summarize_counts(family)$daughters), c(28, 60))
  expect_equal(summarize_counts(family, "direct_parent_rows")$rows, 0)
  family <- rows[rows$husband_id == "ramayan::kumbhakarna", ]
  expect_equal(summarize_counts(family)$sons, 3)
  expect_setequal(family$wife, c("Vajrajwala", "Karkati"))
  family <- rows[rows$husband_id == "sundiata::maghan_kon_fatta", ]
  expect_equal(nrow(family), 3)
  expect_equal(c(summarize_counts(family)$sons, summarize_counts(family)$daughters), c(3, 3))
  expect_identical(record(rows, "Ji Chang (Fengshen Yanyi family account)")$n_sons, "100")
  expect_identical(
    record(variant("ji_chang_shiji_tai_si_ten"), "Ji Chang (Fengshen Yanyi family account)")$n_sons,
    "10"
  )
  expect_identical(record(rows, "King Zhou and Queen Jiang")$sons, "Yin Jiao, Yin Hong")
  wen <- record(rows, "Ji Chang (Fengshen Yanyi family account)")
  expect_fields(rows, wen$parents, row_type = "multi_wife_agg", wife = "multiple", alternate_n_sons = "10")
  expect_equal(lengths(regmatches(wen$sons, gregexpr("Lei Zhenzi", wen$sons, fixed = TRUE))), 1)
  for (version in list(rows, variant("vishwamitra_bhagavata_household"))) {
    family <- version[version$husband_id == "ramayan::vishwamitra", ]
    expect_equal(nrow(family), 2)
    expect_equal(summarize_counts(family)$daughters, 1)
    expect_identical(family$wife[nzchar(family$daughters)], "Menaka")
  }
})

test_that("alternative origins and celibacy are kept distinct from childlessness", {
  versions <- list(repository$children, variant("ukehi_ritual_performer"))
  for (i in 1:2) {
    a <- record(versions[[i]], "Amaterasu (ukehi claimed offspring)")
    b <- record(versions[[i]], "Susanoo (ukehi claimed offspring)")
    x <- summarize_counts(rbind(a, b))
    expect_equal(c(x$sons, x$daughters), c(5, 3))
    expect_identical(a$husband, "none")
    expect_identical(a$wife, "Amaterasu")
    expect_totals(a, c(5, 0)[i], c(0, 3)[i])
    expect_identical(a$row_type, "single_divine")
    expect_identical(b$row_type, "single_divine")
  }
  changed <- variant("mahavira_digambara_celibacy")
  row <- record(changed, "Mahavira (24th Tirthankara) and Yashoda")
  expect_identical(unlist(row[count_fields], use.names = FALSE), rep("0", 3))
  expect_identical(row$sons, "")
  expect_identical(row$daughters, "")
  for (version in list(repository$children, variant("cuchulainn_human_parentage"))) {
    family <- version[version$wife_id == "celtic::deichtine", ]
    expect_equal(summarize_counts(family)$sons, 1)
  }
})

test_that("Ravana and Constantine alternatives preserve identities and mothers", {
  versions <- list(repository$children, variant("mandodari_mani_three"))
  for (i in 1:2) {
    family <- subset(versions[[i]], husband_id == "ramayan::ravana")
    sons <- unlist(strsplit(family$sons, "; ", fixed = TRUE))
    sons <- sons[nzchar(sons)]
    expect_equal(length(sons), 6)
    expect_equal(length(unique(sons)), 6)
    expect_equal(summarize_counts(family)$sons, 6)
    expect_identical(family$wife[child_matches(family, "Atikaya")], c("Dhanyamalini", "Mandodari")[i])
    expect_identical(family$wife[child_matches(family, "Aksha (Akshayakumara)")], c("unknown", "Mandodari")[i])
  }
  father <- record(repository$children, "Constantine and Fausta")$husband_id
  versions <- list(repository$children, variant("constantine_ii_mother_unassigned"))
  for (i in 1:2) {
    family <- versions[[i]][versions[[i]]$husband_id == father, ]
    expect_totals(family, 4, 2)
    expect_identical(family$wife[grepl("Constantine II", family$sons, fixed = TRUE)], c("Fausta", "unknown")[i])
    expect_fields(family, "Constantine and Minervina", sons = "Crispus")
  }
})

test_that("Norse and Kojiki records distinguish direct births from other kin", {
  rows <- repository$children
  expect_fields(rows, "Odin and Frigg", sons = "Baldr")
  expect_fields(rows, "Thor and Sif", n_sons = "0")
  expect_fields(rows, "Sif and father of Ullr (unnamed)", sons = "Ullr", husband = "unknown", wife = "Sif")
  expect_fields(rows, "Njord and his unnamed sister", n_sons = "1", n_daughters = "1", wife_id = "")
  expect_false("Njord and Skadi" %in% rows$parents)
  row <- record(rows, "Izanagi and Izanami (direct deity births)")
  expect_equal(as.numeric(row[count_fields]), c(12, 4, 2))
  expect_length(strsplit(row$sons, "; ", fixed = TRUE)[[1]], 12)
  expect_length(strsplit(row$daughters, "; ", fixed = TRUE)[[1]], 4)
  expect_match(row$daughters, "Hayaakitsuhime", fixed = TRUE)
  expect_match(row$daughters, "Ogetsuhime", fixed = TRUE)
  expect_false(grepl("Foam-Calm", paste(row$sons, row$daughters), fixed = TRUE))
  expect_false(grepl("Great-Vale-Princess", row$daughters, fixed = TRUE))
  parent <- "Louhi (children in Runo 38; father unassigned)"
  expect_fields(rows, parent, n_sons = "1", n_daughters = "2")
  expect_fields(variant("louhi_two_daughters_scope"), parent,
    n_sons = "0", n_daughters = "2", daughters = record(rows, parent)$daughters
  )
})

test_that("Quraysh maternal assignments and aliases do not duplicate children", {
  rows <- repository$children
  family <- subset(rows, husband == "Abu Sufyan")
  expect_equal(nrow(family), 3)
  expect_totals(family, 4, 4)
  expect_identical(family$wife[child_matches(family, "Yazid")], "Zaynab bint Nawfal")
  expect_identical(family$wife[child_matches(family, "Umm Habibah (Ramla)", "daughters")], "Safiyyah bint Abi al-As")
  expect_identical(family$wife[child_matches(family, "Muawiya")], "Hind bint Utbah")
  family <- subset(rows, husband == "Abd al-Rahman ibn Awf")
  expect_equal(nrow(family), 4)
  sons <- unlist(strsplit(family$sons, "; ", fixed = TRUE))
  expect_length(sons, 7)
  expect_length(unique(sons), 7)
  expect_fields(family, "Abd al-Rahman ibn Awf and Tumadur", sons = "Abu Salama (Abdullah al-Asghar)")
  expect_setequal(
    family$wife[grepl("Salim", family$sons, fixed = TRUE)],
    c("Umm Kulthum bint Utba", "Sahla bint Suhayl")
  )
  expect_totals(subset(rows, husband == "Abd Manaf"), 5, 6)
  expect_false(grepl("Nawfal", record(rows, "Abd Manaf and Atikah bint Murrah")$sons, fixed = TRUE))
  expect_fields(rows, "Abd Manaf and Waqidah", sons = "Nawfal")
  family <- subset(rows, husband == "Abd al-Muttalib")
  expect_equal(nrow(family), 5)
  expect_totals(family, 10, 6)
  row <- record(family, "Abd al-Muttalib and Hala bint Uhayb")
  expect_identical(row$n_sons, "3")
  expect_equal(lengths(regmatches(row$sons, gregexpr("al-Ghaydaq", row$sons, fixed = TRUE))), 1)
  expect_fields(rows, "Abbas and Lubaba bint al-Harith", n_sons = "6", n_daughters = "1")
  expect_false(grepl("Kathir", record(rows, "Abbas and Lubaba bint al-Harith")$sons, fixed = TRUE))
  expect_fields(rows, "Abbas and Musliyah", sons = "Kathir; Tammam")
  expect_fields(rows, "Abu Talib and Fatimah bint Asad", n_sons = "4", n_daughters = "3")
  expect_match(record(rows, "Abu Talib and Fatimah bint Asad")$daughters, "Raytah (Asma)", fixed = TRUE)
  expect_false(grepl("Tulayq", record(rows, "Abu Talib and Fatimah bint Asad")$sons, fixed = TRUE))
  expect_fields(rows, "Abu Talib and Illah", sons = "Tulayq")
})

test_that("Hamza and Sad accounts retain separate maternal groups", {
  versions <- list(repository$children, variant("hamza_khawla_biography"))
  for (i in 1:2) {
    family <- subset(versions[[i]], husband == "Hamza")
    expect_equal(nrow(family), 3)
    expect_identical(
      family$wife[child_matches(family, "Ya'la")], c("daughter of al-Milla ibn Malik", "Khawla bint Qays")[i]
    )
    expect_totals(family, 3, c(1, 3)[i])
    expect_fields(family, "Hamza and Salma bint Umays", daughters = "Umama")
  }
  family <- subset(repository$children, husband == "Sa'd ibn Abi Waqqas")
  expect_equal(nrow(family), 12)
  expect_totals(family, 18, 18)
  expect_false("Sa'd ibn Abi Waqqas and wife (unnamed)" %in% family$parents)
  expect_fields(family, "Sa'd ibn Abi Waqqas and Salma of Taghlib", sons = "Abdullah")
  expect_fields(family, "Sa'd ibn Abi Waqqas and Salma bint Khasafa", sons = "Umayr al-Asghar; Amr; Imran")
  expect_fields(family, "Sa'd ibn Abi Waqqas (remaining mothers; Ibn Sa'd)",
    daughters = "Amra; Aisha", row_type = "multi_wife_agg"
  )
})

test_that("imam maternal assignments retain named and unassigned children", {
  rows <- repository$children
  for (case in list(
    c("Ali Zayn al-Abidin and Umm Abdullah bint al-Hasan", "Muhammad al-Baqir"),
    c("Musa al-Kadhim and Umm al-Banin", "Ali al-Ridha"),
    c("Ali al-Hadi and Hadith", "Hasan al-Askari")
  )) {
    expect_fields(rows, case[1], n_sons = "1", sons = case[2], n_daughters = "0")
  }
  expect_fields(rows, "Muhammad al-Baqir and Umm Farwa", n_daughters = "0")
  expect_match(record(rows, "Muhammad al-Baqir (remaining mothers; al-Mufid)")$daughters, "Umm Salama", fixed = TRUE)
  revised <- record(variant("musa_irshad_english_37"), "Musa al-Kadhim (remaining mothers; al-Mufid)")
  expect_false(child_matches(revised, "Kulthum", "daughters"))
  expect_true(child_matches(revised, "Umm Kulthum", "daughters"))
  changed <- variant("ali_irshad_27")
  expect_fields(rows, "Ali and Asma bint Umays", n_sons = "2")
  expect_fields(changed, "Ali and Asma bint Umays", sons = "Yahya")
  expect_match(record(changed, "Ali and Layla bint Mas'ud")$sons, "Muhammad the younger (Abu Bakr)", fixed = TRUE)
  expect_fields(changed, "Ali and Amamah bint Abi al-As", n_sons = "0")
  for (version in list(rows, changed)) expect_fields(version, "Ali (daughters by unnamed mothers)", n_sons = "0")
})

test_that("separate births and origin accounts retain their assigned parents", {
  rows <- repository$children
  for (case in list(
    c("Sukesha", "Vidyutkesha and Salakatankata"), c("Jalandhara", "Shiva (other origins)"),
    c("Ayyappa", "Shiva and Mohini"), c("Jayanti", "Indra and mother of Jayanti (unnamed)")
  )) {
    expect_identical(rows$parents[grepl(case[1], paste(rows$sons, rows$daughters), fixed = TRUE)], case[2])
  }
  expect_fields(rows, "Indra and Shachi", n_sons = "3")
  expect_fields(rows, "Kashyapa and Diti", n_sons = "51")
  expect_fields(rows, "Bali (Mahabali) and Ashana", n_sons = "100")
  expect_fields(rows, "David and Bathsheba", n_sons = "5")
  expect_fields(rows, "Shantanu and Ganga", n_sons = "8")
  family <- subset(rows, husband_id == "hebrew_bible::gideon")
  expect_equal(nrow(family), 2)
  expect_equal(summarize_counts(family)$sons, 71)
  expect_false(grepl("Abimelech", record(family, "Gideon (many wives)")$sons, fixed = TRUE))
  expect_fields(rows, "Husayn ibn Ali and Rabab", daughters = "Sukayna")
  expect_fields(rows, "Uthman and Ramlah bint Shaybah", n_sons = "0", n_daughters = "3")
  expect_fields(rows, "Uthman and Fatimah bint al-Walid", n_sons = "2", n_daughters = "1")
  expect_false(grepl("Umm Sa'id", record(rows, "Uthman and Fatimah bint al-Walid")$sons, fixed = TRUE))
  expect_fields(rows, "Hosea and Gomer", n_sons = "2", n_unknown_sex = "0")
  expect_fields(rows, "Levi and wife (unnamed)", n_daughters = "1", daughters = "Jochebed")
  expect_identical(rows$wife[rows$sons == "Siyavash"], "unknown")
})

test_that("Egyptian and Arthurian variants preserve genealogical generations", {
  rows <- repository$children
  anubis <- subset(rows, epic == "egyptian" & sons == "Anubis")
  expect_identical(anubis$husband, "Osiris")
  expect_identical(anubis$wife, "Nephthys")
  expect_fields(rows, "Horus and Isis (four sons)", wife_id = "egyptian::isis", n_sons = "4")
  changed <- variant("nut_plutarch_epagomenal")
  versions <- list(rows, changed)
  for (i in 1:2) {
    family <- subset(versions[[i]], wife_id == "egyptian::nut")
    expect_totals(family, c(2, 3)[i], 2)
    children <- unlist(strsplit(c(family$sons, family$daughters), "; ", fixed = TRUE))
    children <- children[nzchar(children)]
    expect_length(children, c(4, 5)[i])
    expect_length(unique(children), length(children))
  }
  expect_fields(changed, "Sun and Nut (Rhea; Plutarch)", sons = "Osiris; Arueris (elder Horus)")
  expect_fields(changed, "Hermes and Nut (Rhea; Plutarch)", daughters = "Isis")
  expect_fields(changed, "Geb and Nut", sons = "Set (Typhon)")
  changed <- variant("arthur_geoffrey_genealogy")
  versions <- list(rows, changed)
  for (i in 1:2) {
    family <- subset(versions[[i]], epic == "arthurian")
    expect_identical(
      family$parents[grepl("Mordred", family$sons, fixed = TRUE)],
      c("Arthur and Morgause", "Lot and Anne (Mordred; Geoffrey)")[i]
    )
    expect_totals(family, 3, i - 1)
    expect_fields(family, "Lancelot and Elaine of Corbenic", sons = "Galahad")
  }
  expect_fields(changed, "Uther Pendragon and Igraine", daughters = "Anne (Anna)")
})

test_that("Shahnameh, Sundiata and Ramayana splits conserve named children", {
  rows <- repository$children
  expect_equal(summarize_counts(subset(rows, husband_id == "shahnameh::fereydun"))$sons, 3)
  expect_fields(rows, "Fereydun and Arnavaz", sons = "Iraj")
  expect_fields(rows, "Fereydun and Shahrnaz", sons = "Salm; Tur")
  family <- subset(rows, husband_id == "shahnameh::bahman")
  expect_equal(summarize_counts(family)$sons, 2)
  expect_identical(family$parents[grepl("Darab", family$sons, fixed = TRUE)], "Bahman and Homay")
  versions <- list(rows, variant("katayun_farshidvard_reading"))
  for (i in 1:2) {
    family <- subset(versions[[i]], husband_id == "shahnameh::goshtasp")
    expect_fields(family, "Goshtasp and Katayun", sons = c("Esfandiyar, Pashotan", "Esfandiyar; Farshidvard")[i])
    expect_totals(family, 7, 2)
    for (child in c("Pashotan", "Farshidvard")) expect_equal(sum(grepl(child, family$sons, fixed = TRUE)), 1)
  }
  family <- subset(rows, husband_id == "sundiata::maghan_kon_fatta")
  for (case in list(
    c("Sassouma Berete", "Dankaran Touman", "Nana Triban"),
    c("Sogolon", "Sundiata (Mari Djata)", "Sogolon Kolonkan; Sogolon Djamarou"),
    c("Namandje Kamara", "Manding Bory (Manding Bakary)", "")
  )) {
    expect_identical(family$sons[family$wife == case[1]], case[2])
    expect_identical(family$daughters[family$wife == case[1]], case[3])
  }
  expect_fields(rows, "Kumbhakarna and Vajrajwala", sons = "Kumbha; Nikumbha")
  expect_fields(rows, "Kumbhakarna and Karkati", sons = "Bhimasura (Bhima)")
  expect_fields(rows, "Vali and Tara", husband_id = "ramayan::vali")
})

test_that("remaining source alternatives retain attribution and counting scope", {
  rows <- repository$children
  for (case in list(
    c("vulcan_cicero_jupiter", "Vulcan", "Juno (Vulcan without a father)", "Jupiter and Juno"),
    c("aeneas_livy_lavinia", "Silvius", "Aeneas and Lavinia", "Ascanius and mother of Silvius (unnamed)")
  )) {
    versions <- list(rows, variant(case[1]))
    for (i in 1:2) {
      family <- subset(versions[[i]], epic == "roman")
      expect_identical(family$parents[child_matches(family, case[2])], case[i + 2])
    }
  }
  expect_fields(rows, "Jupiter and Metis", row_type = "cross_tradition")
  expect_fields(rows, "Zeus and Persephone", family_id = "zeus_persephone_melinoe")
  expect_fields(rows, "Jupiter and Proserpina (Melinoe hymn)",
    family_id = "zeus_persephone_melinoe", row_type = "cross_tradition"
  )
  expect_equal(summarize_counts(
    record(rows, "Jupiter and Proserpina (Melinoe hymn)"),
    "exclude_mythical_and_cross"
  )$daughters, 0)
  expect_match(record(rows, "Siddhartha and Trishala")$sons, "Nandivardhana", fixed = TRUE)
  expect_fields(rows, "Mahavira (24th Tirthankara) and Yashoda", n_daughters = "1")
  versions <- list(rows, variant("cuchulainn_human_parentage"))
  for (i in 1:2) {
    family <- subset(versions[[i]], wife_id == "celtic::deichtine")
    expect_identical(family$husband[family$sons == "Cú Chulainn"], c("Lugh", "Sualtaim")[i])
  }
  expect_fields(variant("begil_literal_plural_minimum"), "Begil and wife (unnamed)", n_sons = "2", n_daughters = "2")
  expect_fields(variant("ushun_formulaic_daughter"), "Ushun Koja and wife (unnamed)", n_daughters = "0")
  expect_fields(rows, "Oghuz Khan (six sons; mothers unassigned)",
    epic = "oguzname", row_type = "multi_wife_agg", n_sons = "6"
  )
  expect_fields(rows, "Li Jing and Lady Yin", n_sons = "3")
  expect_fields(rows, "King Amarashakti (three sons; mothers unassigned)", n_sons = "3", row_type = "multi_wife_agg")
  versions <- list(rows, variant("vishwamitra_bhagavata_household"))
  for (i in 1:2) {
    family <- subset(versions[[i]], husband_id == "ramayan::vishwamitra")
    expect_equal(summarize_counts(family)$sons, c(105, 102)[i])
    expect_equal(summarize_counts(family, "exclude_mythical")$daughters, 1)
  }
})
