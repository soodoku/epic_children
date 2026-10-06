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
