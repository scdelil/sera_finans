import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin bildirimMotoru = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

  if (Platform.isAndroid) {
    const androidAyar = AndroidInitializationSettings('@mipmap/ic_launcher');
    const baslatmaAyari = InitializationSettings(android: androidAyar);
    await bildirimMotoru.initialize(settings: baslatmaAyari);
  }

  runApp(const SeraFinansApp());
}

class SeraFinansApp extends StatelessWidget {
  const SeraFinansApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sera Finans - Personal CFO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A1412),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF12221F),
          error: Color(0xFFEF4444),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF162925),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF233E38), width: 1),
          ),
        ),
      ),
      home: const AnaIskelet(),
    );
  }
}

// --- VERİ MODELLERİ (JSON KALICI HAFIZA DESTEKLİ) ---
class Islem {
  final String baslik;
  final double tutar;
  final bool gelirMi;
  final String kategori;
  final DateTime tarih;

  Islem({
    required this.baslik,
    required this.tutar,
    required this.gelirMi,
    required this.kategori,
    required this.tarih,
  });

  Map<String, dynamic> toJson() => {
        'baslik': baslik,
        'tutar': tutar,
        'gelirMi': gelirMi,
        'kategori': kategori,
        'tarih': tarih.toIso8601String(),
      };

  factory Islem.fromJson(Map<String, dynamic> json) => Islem(
        baslik: json['baslik'] ?? '',
        tutar: (json['tutar'] as num?)?.toDouble() ?? 0.0,
        gelirMi: json['gelirMi'] ?? false,
        kategori: json['kategori'] ?? 'Genel',
        tarih: DateTime.tryParse(json['tarih'] ?? '') ?? DateTime.now(),
      );
}

class SabitGelir {
  final String ad;
  final double tutar;

  SabitGelir({required this.ad, required this.tutar});

  Map<String, dynamic> toJson() => {'ad': ad, 'tutar': tutar};

  factory SabitGelir.fromJson(Map<String, dynamic> json) => SabitGelir(
        ad: json['ad'] ?? '',
        tutar: (json['tutar'] as num?)?.toDouble() ?? 0.0,
      );
}

class SabitIhtiyac {
  final String ad;
  final double tutar;
  final String sonGun;
  bool odendi;

  SabitIhtiyac({
    required this.ad,
    required this.tutar,
    required this.sonGun,
    this.odendi = false,
  });

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'tutar': tutar,
        'sonGun': sonGun,
        'odendi': odendi,
      };

  factory SabitIhtiyac.fromJson(Map<String, dynamic> json) => SabitIhtiyac(
        ad: json['ad'] ?? '',
        tutar: (json['tutar'] as num?)?.toDouble() ?? 0.0,
        sonGun: json['sonGun'] ?? 'Bu ay',
        odendi: json['odendi'] ?? false,
      );
}

class WishUrun {
  final String ad;
  final double fiyat;
  final String not;
  final int renkDegeri;
  String? gorselYolu;

  WishUrun({
    required this.ad,
    required this.fiyat,
    required this.not,
    this.renkDegeri = 0xFF10B981,
    this.gorselYolu,
  });

  Color get renk => Color(renkDegeri);

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'fiyat': fiyat,
        'not': not,
        'renkDegeri': renkDegeri,
        'gorselYolu': gorselYolu,
      };

  factory WishUrun.fromJson(Map<String, dynamic> json) => WishUrun(
        ad: json['ad'] ?? '',
        fiyat: (json['fiyat'] as num?)?.toDouble() ?? 0.0,
        not: json['not'] ?? '',
        renkDegeri: json['renkDegeri'] ?? 0xFF10B981,
        gorselYolu: json['gorselYolu'],
      );
}

// --- ANA EKRAN VE DURUM YÖNETİMİ ---
class AnaIskelet extends StatefulWidget {
  const AnaIskelet({super.key});

  @override
  State<AnaIskelet> createState() => _AnaIskeletState();
}

class _AnaIskeletState extends State<AnaIskelet> {
  int _seciliSekme = 0;
  bool _yukleniyor = true;
  bool _ingilizceMi = false;
  final ImagePicker _picker = ImagePicker();

  // Finans Verileri
  double _kasaBakiyesi = 0.0;
  double _birikimHavuzu = 0.0;
  double _kurtarilanPara = 0.0;
  bool _bahceCurudu = false;
  double _bugunHarcanan = 0.0;
  String _sonAktifTarih = '';
  int _paraGelisGunu = 15;

  // Su & Hidrasyon Verileri
  int _icilenSuMl = 0;
  int _gunlukSuHedefiMl = 2000;
  bool _suHatirlaticiAktif = true;
  int _suHatirlatmaAraligiSaat = 2;
  int _suBaslangicSaati = 9;
  int _suBitisSaati = 23;

  List<SabitGelir> _sabitGelirler = [];
  List<Islem> _islemler = [];
  List<SabitIhtiyac> _ihtiyaclar = [];
  List<WishUrun> _wishListesi = [];

  // --- ÇİFT DİL (TR / EN) YARDIMCISI ---
  String _t(String tr, String en) => _ingilizceMi ? en : tr;

  String _kategoriEtiketi(String kat) {
    if (!_ingilizceMi) return kat;
    switch (kat) {
      case 'Sabit Gelir':
        return 'Recurring Income';
      case 'Gelir':
        return 'Income';
      case 'Harcama':
        return 'Expense';
      case 'Yatırım':
        return 'Savings';
      case 'Zorunlu İhtiyaç':
        return 'Essential Need';
      case 'Keyfi Alışveriş':
        return 'Impulse Purchase';
      default:
        return kat;
    }
  }

  Future<void> _diliDegistir() async {
    setState(() {
      _ingilizceMi = !_ingilizceMi;
    });
    await _verileriKaydet();
    await _suBildirimleriniPlanla(izinIste: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          _t('Dil Türkçe olarak ayarlandı.', 'Language switched to English.'),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  String _bugunTarihAnahtari() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // --- KALICI HAFIZA OKUMA / YAZMA ---
  Future<void> _verileriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final bugunAnahtar = _bugunTarihAnahtari();
    final kayitliTarih = prefs.getString('sonAktifTarih') ?? bugunAnahtar;

    setState(() {
      _ingilizceMi = prefs.getBool('ingilizceMi') ?? false;
      _kasaBakiyesi = prefs.getDouble('kasaBakiyesi') ?? 0.0;
      _birikimHavuzu = prefs.getDouble('birikimHavuzu') ?? 0.0;
      _kurtarilanPara = prefs.getDouble('kurtarilanPara') ?? 0.0;
      _bahceCurudu = prefs.getBool('bahceCurudu') ?? false;
      _paraGelisGunu = prefs.getInt('paraGelisGunu') ?? 15;

      _gunlukSuHedefiMl = prefs.getInt('gunlukSuHedefiMl') ?? 2000;
      _suHatirlaticiAktif = prefs.getBool('suHatirlaticiAktif') ?? true;
      _suHatirlatmaAraligiSaat = prefs.getInt('suHatirlatmaAraligiSaat') ?? 2;
      _suBaslangicSaati = prefs.getInt('suBaslangicSaati') ?? 9;
      _suBitisSaati = prefs.getInt('suBitisSaati') ?? 23;

      _sonAktifTarih = bugunAnahtar;

      if (kayitliTarih == bugunAnahtar) {
        _bugunHarcanan = prefs.getDouble('bugunHarcanan') ?? 0.0;
        _icilenSuMl = prefs.getInt('icilenSuMl') ?? 0;
      } else {
        _bugunHarcanan = 0.0;
        _icilenSuMl = 0;
      }

      final sgStr = prefs.getString('sabitGelirler');
      if (sgStr != null) {
        final List decoded = jsonDecode(sgStr);
        _sabitGelirler = decoded.map((e) => SabitGelir.fromJson(e)).toList();
      }

      final islemStr = prefs.getString('islemler');
      if (islemStr != null) {
        final List decoded = jsonDecode(islemStr);
        _islemler = decoded.map((e) => Islem.fromJson(e)).toList();
      }

      final ihtStr = prefs.getString('ihtiyaclar');
      if (ihtStr != null) {
        final List decoded = jsonDecode(ihtStr);
        _ihtiyaclar = decoded.map((e) => SabitIhtiyac.fromJson(e)).toList();
      }

      final wishStr = prefs.getString('wishListesi');
      if (wishStr != null) {
        final List decoded = jsonDecode(wishStr);
        _wishListesi = decoded.map((e) => WishUrun.fromJson(e)).toList();
      }

      _yukleniyor = false;
    });

    if (kayitliTarih != bugunAnahtar) {
      await _verileriKaydet();
    }

    await _suBildirimleriniPlanla(izinIste: true);
  }

  Future<void> _verileriKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ingilizceMi', _ingilizceMi);
    await prefs.setDouble('kasaBakiyesi', _kasaBakiyesi);
    await prefs.setDouble('birikimHavuzu', _birikimHavuzu);
    await prefs.setDouble('kurtarilanPara', _kurtarilanPara);
    await prefs.setBool('bahceCurudu', _bahceCurudu);
    await prefs.setDouble('bugunHarcanan', _bugunHarcanan);
    await prefs.setString('sonAktifTarih', _bugunTarihAnahtari());
    await prefs.setInt('paraGelisGunu', _paraGelisGunu);

    await prefs.setInt('icilenSuMl', _icilenSuMl);
    await prefs.setInt('gunlukSuHedefiMl', _gunlukSuHedefiMl);
    await prefs.setBool('suHatirlaticiAktif', _suHatirlaticiAktif);
    await prefs.setInt('suHatirlatmaAraligiSaat', _suHatirlatmaAraligiSaat);
    await prefs.setInt('suBaslangicSaati', _suBaslangicSaati);
    await prefs.setInt('suBitisSaati', _suBitisSaati);

    await prefs.setString('sabitGelirler', jsonEncode(_sabitGelirler.map((e) => e.toJson()).toList()));
    await prefs.setString('islemler', jsonEncode(_islemler.map((e) => e.toJson()).toList()));
    await prefs.setString('ihtiyaclar', jsonEncode(_ihtiyaclar.map((e) => e.toJson()).toList()));
    await prefs.setString('wishListesi', jsonEncode(_wishListesi.map((e) => e.toJson()).toList()));
  }

  // --- CFO SU HATIRLATICI BİLDİRİM MOTORU ---
  Future<void> _suBildirimleriniPlanla({bool izinIste = false}) async {
    if (!Platform.isAndroid) return;

    final androidPlugin = bildirimMotoru
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (izinIste && androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    await bildirimMotoru.cancelAll();
    if (!_suHatirlaticiAktif) return;

    final androidDetay = AndroidNotificationDetails(
      'sera_su_kanali',
      _t('CFO Su Hatırlatıcıları', 'CFO Hydration Reminders'),
      channelDescription: _t(
        'Günlük su tüketimi ve sera nemi uyarıları',
        'Daily water intake and greenhouse humidity alerts',
      ),
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    final bildirimDetay = NotificationDetails(android: androidDetay);

    final cfoSuMesajlari = _ingilizceMi
        ? [
            'Founder, liquidity drop detected in body reserves. Drink 1 glass (250 ml) of water for peak efficiency.',
            'Greenhouse Report: Your plants need water, and so do you. Grab a glass of water now!',
            'CFO Alert: A dehydrated brain makes budget mistakes. Time to hydrate yourself and the greenhouse.',
            'Reminder: Reaching your daily water goal boosts greenhouse dew to 100%. Add 250 ml!',
          ]
        : [
            'Sayın Kurucu, vücut rezervlerinde likidite düşüşü tespit edildi. Operasyonel verimlilik için 1 bardak (250 ml) su tüketin.',
            'Sera Raporu: Bahçedeki bitkiler kadar sizin de suya ihtiyacınız var. Kalkıp 1 bardak su için!',
            'CFO Uyarısı: Susuz kalan beyin bütçe hatası yapar. Kendinizi ve serayı nemlendirme zamanı.',
            'Hatırlatma: Günlük su hedefinize ulaşmak bahçedeki çiy oranını %100 yapar. 250 ml ekleyin!',
          ];

    final simdi = tz.TZDateTime.now(tz.local);
    int planlananAdet = 0;

    for (int saatFarki = 1; saatFarki <= 48 && planlananAdet < 18; saatFarki++) {
      if (saatFarki % _suHatirlatmaAraligiSaat != 0) continue;

      final hedefZaman = simdi.add(Duration(hours: saatFarki));
      if (hedefZaman.hour >= _suBaslangicSaati && hedefZaman.hour < _suBitisSaati) {
        final mesaj = cfoSuMesajlari[planlananAdet % cfoSuMesajlari.length];
        await bildirimMotoru.zonedSchedule(
          id: 1000 + planlananAdet,
          title: _t('💧 CFO Hidrasyon Brifingi', '💧 CFO Hydration Briefing'),
          body: mesaj,
          scheduledDate: hedefZaman,
          notificationDetails: bildirimDetay,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        planlananAdet++;
      }
    }
  }

  Future<void> _testSuBildirimiGonder() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Sistem bildirimleri Android telefonda çalışır; Windows üzerinde simüle edildi.',
              'System notifications run on Android devices; simulated on Windows.',
            ),
          ),
        ),
      );
      return;
    }

    final androidPlugin = bildirimMotoru
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final androidDetay = AndroidNotificationDetails(
      'sera_su_kanali',
      _t('CFO Su Hatırlatıcıları', 'CFO Hydration Reminders'),
      channelDescription: _t(
        'Günlük su tüketimi ve sera nemi uyarıları',
        'Daily water intake and greenhouse humidity alerts',
      ),
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await bildirimMotoru.show(
      id: 999,
      title: _t('💧 CFO Hidrasyon Testi', '💧 CFO Hydration Test'),
      body: _t(
        'Sayın Kurucu, bildirim hattı aktif! Serayı nemlendirmek için 1 bardak su içmeyi unutmayın.',
        'Founder, the notification line is live! Don\'t forget to drink a glass of water to humidify the greenhouse.',
      ),
      notificationDetails: NotificationDetails(android: androidDetay),
    );
  }

  void _suEkle(int miktarMl) {
    final oncekiHedefTamamMi = _icilenSuMl >= _gunlukSuHedefiMl;
    setState(() {
      _gunKontrolEt();
      _icilenSuMl = (_icilenSuMl + miktarMl).clamp(0, 10000);
    });
    _verileriKaydet();

    if (!oncekiHedefTamamMi && _icilenSuMl >= _gunlukSuHedefiMl) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0284C7),
          content: Text(
            _t(
              '💧 Günlük su hedefine ulaştın! Seradaki nem ve çiy oranı %100 oldu!',
              '💧 Daily hydration goal reached! Greenhouse dew and humidity are now at 100%!',
            ),
          ),
        ),
      );
    }
  }

  void _suAyarlariDialog() {
    int secilenHedef = _gunlukSuHedefiMl;
    bool bildirimAcik = _suHatirlaticiAktif;
    int secilenAralik = _suHatirlatmaAraligiSaat;
    int baslangic = _suBaslangicSaati;
    int bitis = _suBitisSaati;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF162925),
          title: Row(
            children: [
              const Icon(Icons.water_drop_rounded, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_t('Su & CFO Bildirim Ayarları', 'Water & CFO Alert Settings')),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _t('Arka Plan Hatırlatıcıları', 'Background Reminders'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    _t(
                      'Uygulama kapalıyken CFO su uyarısı gönderir',
                      'Sends CFO hydration alerts even when the app is closed',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: bildirimAcik,
                  onChanged: (val) => setDialogState(() => bildirimAcik = val),
                ),
                const Divider(),
                Text(
                  _t('Günlük Su Hedefi', 'Daily Water Goal'),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [1500, 2000, 2500, 3000].map((ml) {
                    return ChoiceChip(
                      label: Text('${(ml / 1000).toStringAsFixed(1)} L'),
                      selected: secilenHedef == ml,
                      selectedColor: const Color(0xFF38BDF8),
                      labelStyle: TextStyle(
                        color: secilenHedef == ml ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) => setDialogState(() => secilenHedef = ml),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  _t('Hatırlatma Sıklığı', 'Reminder Interval'),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [1, 2, 3, 4].map((saat) {
                    return ChoiceChip(
                      label: Text(_t('$saat Saatte Bir', 'Every ${saat}h')),
                      selected: secilenAralik == saat,
                      selectedColor: const Color(0xFF10B981),
                      labelStyle: TextStyle(
                        color: secilenAralik == saat ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setDialogState(() => secilenAralik = saat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  _t('Aktif Saatler (Gece Uyku Koruması)', 'Active Hours (Sleep Protection)'),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: baslangic,
                        dropdownColor: const Color(0xFF162925),
                        decoration: InputDecoration(
                          labelText: _t('Başlangıç', 'Start'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: List.generate(13, (i) => i + 6)
                            .map((h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => baslangic = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: bitis,
                        dropdownColor: const Color(0xFF162925),
                        decoration: InputDecoration(
                          labelText: _t('Bitiş', 'End'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: List.generate(7, (i) => i + 18)
                            .map((h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => bitis = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _testSuBildirimiGonder,
                    icon: const Icon(Icons.notifications_active_outlined, size: 18, color: Color(0xFFF59E0B)),
                    label: Text(_t('Test Bildirimi Gönder', 'Send Test Notification')),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('İptal', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _gunlukSuHedefiMl = secilenHedef;
                  _suHatirlaticiAktif = bildirimAcik;
                  _suHatirlatmaAraligiSaat = secilenAralik;
                  _suBaslangicSaati = baslangic;
                  _suBitisSaati = bitis <= baslangic ? baslangic + 1 : bitis;
                });
                await _verileriKaydet();
                await _suBildirimleriniPlanla(izinIste: true);
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      bildirimAcik
                          ? _t(
                              'CFO su hatırlatıcısı $_suBaslangicSaati:00 - $_suBitisSaati:00 arası $secilenAralik saatte bir kuruldu!',
                              'CFO hydration alert scheduled every ${secilenAralik}h between $_suBaslangicSaati:00 - $_suBitisSaati:00!',
                            )
                          : _t('Arka plan su bildirimleri kapatıldı.', 'Background hydration alerts turned off.'),
                    ),
                  ),
                );
              },
              child: Text(_t('Kaydet', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _gorseliKaliciKopyala(String kaynakYol) async {
    try {
      final klasor = await getApplicationDocumentsDirectory();
      final hedefYol = '${klasor.path}${Platform.pathSeparator}wish_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final kopya = await File(kaynakYol).copy(hedefYol);
      return kopya.path;
    } catch (_) {
      return kaynakYol;
    }
  }

  void _gunKontrolEt() {
    final bugun = _bugunTarihAnahtari();
    if (_sonAktifTarih != bugun) {
      _sonAktifTarih = bugun;
      _bugunHarcanan = 0.0;
      _icilenSuMl = 0;
    }
  }

  void _tumVerileriSifirlaDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(_t('Temiz Başlangıç (Tümünü Sıfırla)', 'Clean Slate (Reset All)')),
        content: Text(
          _t(
            'Kasadaki bakiye, bahçe birikimi, su sayacı, işlemler ve listelerin tamamı sıfırlanacak. Emin misiniz Sayın Kurucu?',
            'Your vault balance, greenhouse savings, water counter, transactions, and lists will all be wiped. Are you sure, Founder?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Vazgeç', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await prefs.setBool('ingilizceMi', _ingilizceMi);
              if (!mounted) return;
              setState(() {
                _kasaBakiyesi = 0.0;
                _birikimHavuzu = 0.0;
                _kurtarilanPara = 0.0;
                _bahceCurudu = false;
                _bugunHarcanan = 0.0;
                _icilenSuMl = 0;
                _paraGelisGunu = 15;
                _sabitGelirler = [];
                _islemler = [];
                _ihtiyaclar = [];
                _wishListesi = [];
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t('Tüm kayıtlar temizlendi. Yeni dönem başladı!', 'All records cleared. A new cycle begins!'),
                  ),
                ),
              );
            },
            child: Text(_t('Evet, Sıfırla', 'Yes, Reset')),
          ),
        ],
      ),
    );
  }

  // --- FİNANSAL HESAPLAMA MOTORU ---
  double get _odenmemisIhtiyacToplami => _ihtiyaclar
      .where((i) => !i.odendi)
      .fold(0.0, (toplam, item) => toplam + item.tutar);

  double get _harcanabilirNetBakiye =>
      (_kasaBakiyesi - _odenmemisIhtiyacToplami).clamp(0.0, double.infinity);

  int get _gelirGununeKalanGun {
    final simdi = DateTime.now();
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);

    final buAySonGun = DateTime(simdi.year, simdi.month + 1, 0).day;
    final buAyHedefGun = math.min(_paraGelisGunu, buAySonGun);
    DateTime hedefTarih = DateTime(simdi.year, simdi.month, buAyHedefGun);

    if (!hedefTarih.isAfter(bugun)) {
      final sonrakiAySonGun = DateTime(simdi.year, simdi.month + 2, 0).day;
      final sonrakiAyHedefGun = math.min(_paraGelisGunu, sonrakiAySonGun);
      hedefTarih = DateTime(simdi.year, simdi.month + 1, sonrakiAyHedefGun);
    }

    return hedefTarih.difference(bugun).inDays.clamp(1, 31);
  }

  double get _gunlukGuvenliLimit =>
      (_harcanabilirNetBakiye + _bugunHarcanan) / _gelirGununeKalanGun;

  bool get _limitAsildiMi => _bugunHarcanan > _gunlukGuvenliLimit && _bugunHarcanan > 0;

  double get _suTamamlanmaOrani =>
      _gunlukSuHedefiMl > 0 ? (_icilenSuMl / _gunlukSuHedefiMl).clamp(0.0, 1.0) : 0.0;

  String get _cfoMesaji {
    if (_kasaBakiyesi == 0 && _birikimHavuzu == 0 && _islemler.isEmpty) {
      return _t(
        'Hoş geldiniz Sayın Kurucu! İlk gelirinizi ve sabit ihtiyaçlarınızı girerek bütçe operasyonunu ve bahçenizi başlatabilirsiniz.',
        'Welcome, Founder! Log your first income and fixed expenses to launch your budget operations and grow your greenhouse.',
      );
    }
    if (_bahceCurudu) {
      return _t(
        'Sayın Kurucu, rezervleri keyfi harcamayla sıfırladığınız için sera kırağı yedi. Ekleyeceğiniz her ₺100 toprağı yeniden yeşertecek.',
        'Founder, draining reserves on impulse purchases caused frostbite in the greenhouse. Every ₺100 saved will revive the soil.',
      );
    }
    if (_limitAsildiMi) {
      final asim = (_bugunHarcanan - _gunlukGuvenliLimit).toStringAsFixed(2);
      return _t(
        'Dikkat Sayın Kurucu: Bugünkü limiti ₺$asim aştık. Seradaki bitkiler susuzluktan boyun büktü, yarın frene basıyoruz.',
        'Alert, Founder: Today\'s limit is exceeded by ₺$asim. Greenhouse plants are wilting from thirst—we hit the brakes tomorrow.',
      );
    }
    final netKalan = (_gunlukGuvenliLimit - _bugunHarcanan).clamp(0, 99999).toStringAsFixed(2);
    if (_odenmemisIhtiyacToplami > 0) {
      return _t(
        'Sayın Kurucu, sabit giderler için ₺${_odenmemisIhtiyacToplami.toStringAsFixed(2)} kilitlendi. Ayın $_paraGelisGunu\'ine kadar ($_gelirGununeKalanGun gün) bugünkü net limitiniz ₺$netKalan.',
        'Founder, ₺${_odenmemisIhtiyacToplami.toStringAsFixed(2)} is locked for fixed bills. With $_gelirGununeKalanGun days until payday (day $_paraGelisGunu), your safe limit today is ₺$netKalan.',
      );
    }
    return _t(
      'Tüm sabit yükümlülükler temizlendi Sayın Kurucu! Ayın $_paraGelisGunu\'ine kadar kasa kontrol altında, bahçedeki her ₺100 yeni bir yaşam filizlendiriyor.',
      'All fixed obligations are cleared, Founder! Cash flow is locked in until day $_paraGelisGunu, and every ₺100 saved sprouts new life in the garden.',
    );
  }

  // --- PARA GELİŞ GÜNÜ SEÇİCİ ---
  void _paraGelisGunuSecDialog() {
    int secilenGun = _paraGelisGunu;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF162925),
          title: Row(
            children: [
              const Icon(Icons.event_repeat_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(_t('Para Geliş Günü', 'Next Payday')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  'Burs, maaş veya harçlığın ayın kaçında yatıyor? Günlük harcama limitin bu güne kalan gün sayısına bölünür.',
                  'Which day of the month does your allowance, grant, or salary arrive? Your daily limit is divided across the remaining days.',
                ),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(31, (index) {
                  final gun = index + 1;
                  final secili = gun == secilenGun;
                  return InkWell(
                    onTap: () => setDialogState(() => secilenGun = gun),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: secili ? const Color(0xFF10B981) : const Color(0xFF0E1C19),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: secili ? const Color(0xFF10B981) : Colors.white12,
                        ),
                      ),
                      child: Text(
                        '$gun',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: secili ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('İptal', 'Cancel'))),
            FilledButton(
              onPressed: () {
                setState(() => _paraGelisGunu = secilenGun);
                _verileriKaydet();
                Navigator.pop(ctx);
              },
              child: Text(_t('Ayın $secilenGun\'i Olarak Ayarla', 'Set as Day $secilenGun')),
            ),
          ],
        ),
      ),
    );
  }

  // --- SABİT GELİR FONKSİYONLARI ---
  void _sabitGelirUygula(SabitGelir gelir) {
    final yeniIslem = Islem(
      baslik: '${gelir.ad} (${_t("Sabit", "Preset")})',
      tutar: gelir.tutar,
      gelirMi: true,
      kategori: 'Sabit Gelir',
      tarih: DateTime.now(),
    );

    setState(() {
      _kasaBakiyesi += gelir.tutar;
      _islemler.insert(0, yeniIslem);
    });
    _verileriKaydet();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            '${gelir.ad} (+₺${gelir.tutar.toStringAsFixed(0)}) kasaya eklendi!',
            '${gelir.ad} (+₺${gelir.tutar.toStringAsFixed(0)}) added to vault!',
          ),
        ),
        action: SnackBarAction(
          label: _t('Geri Al', 'Undo'),
          onPressed: () {
            setState(() {
              _kasaBakiyesi = (_kasaBakiyesi - gelir.tutar).clamp(0.0, double.infinity);
              _islemler.remove(yeniIslem);
            });
            _verileriKaydet();
          },
        ),
      ),
    );
  }

  void _sabitGelirYonetDialog() {
    final adCtrl = TextEditingController();
    final tutarCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF162925),
          title: Text(_t('Sabit Gelir Şablonları', 'Recurring Income Presets')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_sabitGelirler.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _t('Henüz sabit gelir şablonu eklenmedi.', 'No recurring income presets added yet.'),
                      style: const TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  ..._sabitGelirler.map(
                    (sg) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(sg.ad, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('₺${sg.tutar.toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                        onPressed: () {
                          setState(() => _sabitGelirler.remove(sg));
                          _verileriKaydet();
                          setDialogState(() {});
                        },
                      ),
                    ),
                  ),
                const Divider(height: 24),
                TextField(
                  controller: adCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Yeni Sabit Gelir Adı (Örn: Burs)', 'Preset Name (e.g. Grant)'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tutarCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _t('Tutar (₺) - Örn: 4000', 'Amount (₺) - e.g. 4000'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Kapat', 'Close'))),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(_t('Şablon Ekle', 'Add Preset')),
              onPressed: () {
                final tutar = double.tryParse(tutarCtrl.text.replaceAll(',', '.')) ?? 0;
                if (adCtrl.text.trim().isEmpty || tutar <= 0) return;
                setState(() {
                  _sabitGelirler.add(SabitGelir(ad: adCtrl.text.trim(), tutar: tutar));
                });
                _verileriKaydet();
                adCtrl.clear();
                tutarCtrl.clear();
                setDialogState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- İŞLEM FONKSİYONLARI ---
  void _islemEkleDialog(bool gelirMi) {
    final baslikCtrl = TextEditingController();
    final tutarCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(
          gelirMi
              ? _t('Kasaya Gelir Ekle', 'Add Income to Vault')
              : _t('Kuruşu Kuruşuna Harcama Gir', 'Log Penny-by-Penny Expense'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: baslikCtrl,
              decoration: InputDecoration(
                labelText: gelirMi
                    ? _t('Gelir Kaynağı (Örn: Ek İş)', 'Income Source (e.g. Freelance)')
                    : _t('Nereye Harcandı? (Örn: Yemek)', 'Description (e.g. Lunch)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _t('Tutar (₺) - Örn: 142.50', 'Amount (₺) - e.g. 142.50'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('İptal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final tutar = double.tryParse(tutarCtrl.text.replaceAll(',', '.')) ?? 0;
              if (tutar <= 0 || baslikCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);

              if (gelirMi) {
                setState(() {
                  _kasaBakiyesi += tutar;
                  _islemler.insert(
                    0,
                    Islem(
                      baslik: baslikCtrl.text.trim(),
                      tutar: tutar,
                      gelirMi: true,
                      kategori: 'Gelir',
                      tarih: DateTime.now(),
                    ),
                  );
                });
                _verileriKaydet();
              } else {
                _harcamaKaydetVeYuvarlaSor(baslikCtrl.text.trim(), tutar);
              }
            },
            child: Text(_t('Kaydet', 'Save')),
          ),
        ],
      ),
    );
  }

  void _harcamaKaydetVeYuvarlaSor(String baslik, double tutar) {
    final ustOnluk = (tutar / 10).ceil() * 10.0;
    final fark = ustOnluk - tutar;

    setState(() {
      _gunKontrolEt();
      _kasaBakiyesi = (_kasaBakiyesi - tutar).clamp(0.0, double.infinity);
      _bugunHarcanan += tutar;
      _islemler.insert(
        0,
        Islem(
          baslik: baslik,
          tutar: tutar,
          gelirMi: false,
          kategori: 'Harcama',
          tarih: DateTime.now(),
        ),
      );
    });
    _verileriKaydet();

    if (fark >= 1.0 && _kasaBakiyesi >= fark) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF162925),
          title: Row(
            children: [
              const Icon(Icons.water_drop_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(_t('CFO Küsurat Teklifi', 'CFO Round-Up Offer')),
            ],
          ),
          content: Text(
            _t(
              'Harcamayı ₺${ustOnluk.toStringAsFixed(0)} seviyesine yuvarlayıp aradaki ₺${fark.toStringAsFixed(2)} küsuratı bahçeye can suyu olarak aktaralım mı?',
              'Round this expense up to ₺${ustOnluk.toStringAsFixed(0)} and pour the ₺${fark.toStringAsFixed(2)} spare change into your garden?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('Kalsın', 'Skip')),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _kasaBakiyesi -= fark;
                  _birikimHavuzu += fark;
                  _bahceCurudu = false;
                });
                _verileriKaydet();
                Navigator.pop(ctx);
              },
              child: Text(_t('Bahçeye Aktar', 'Water Garden')),
            ),
          ],
        ),
      );
    }
  }

  void _birikimeAktarDialog() {
    final tutarCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(_t('Seraya Sermaye Aktar', 'Invest in Greenhouse')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                'Eklediğin her ₺100 bahçede yeni bir bitki, çiçek veya ağaç dalı filizlendirir.',
                'Every ₺100 added sprouts a new plant, flower, or tree branch in your garden.',
              ),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _t(
                  'Tutar (Maks: ₺${_kasaBakiyesi.toStringAsFixed(0)})',
                  'Amount (Max: ₺${_kasaBakiyesi.toStringAsFixed(0)})',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [100, 250, 500].map((miktar) {
                return ActionChip(
                  label: Text('+₺$miktar'),
                  onPressed: () {
                    if (_kasaBakiyesi >= miktar) {
                      tutarCtrl.text = miktar.toString();
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Vazgeç', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final tutar = double.tryParse(tutarCtrl.text.replaceAll(',', '.')) ?? 0;
              if (tutar <= 0 || tutar > _kasaBakiyesi) return;
              setState(() {
                _kasaBakiyesi -= tutar;
                _birikimHavuzu += tutar;
                _bahceCurudu = false;
                _islemler.insert(
                  0,
                  Islem(
                    baslik: _t('Birikim Bahçesine Transfer', 'Transfer to Savings Garden'),
                    tutar: tutar,
                    gelirMi: false,
                    kategori: 'Yatırım',
                    tarih: DateTime.now(),
                  ),
                );
              });
              _verileriKaydet();
              Navigator.pop(ctx);
            },
            child: Text(_t('Bahçeyi Besle', 'Feed Garden')),
          ),
        ],
      ),
    );
  }

  void _birikimiBozDialog() {
    if (_birikimHavuzu <= 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(_t('Birikimi Sıfırlama Kararı', 'Withdraw Savings Pool')),
        content: Text(
          _t(
            'Kasada ₺${_birikimHavuzu.toStringAsFixed(2)} birikmiş sermayen var. Bu parayı ne amaçla çekiyorsun?',
            'You have ₺${_birikimHavuzu.toStringAsFixed(2)} in your savings pool. Why are you withdrawing it?',
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.verified_rounded, color: Color(0xFF10B981)),
            label: Text(
              _t('Gerekli / Yatırım İçin (Bitkileri Koru)', 'Essential / Investment (Protect Flora)'),
            ),
            onPressed: () {
              setState(() {
                _kasaBakiyesi += _birikimHavuzu;
                _birikimHavuzu = 0;
              });
              _verileriKaydet();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      'CFO Onaylı Stratejik Harcama: Toprak verimi koruma altına alındı!',
                      'CFO-Approved Strategic Spend: Soil fertility protected!',
                    ),
                  ),
                ),
              );
            },
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            icon: const Icon(Icons.local_fire_department_rounded),
            label: Text(
              _t('Boş Beleş Harcadım (Bahçe Çürüsün)', 'Impulse Spend (Freeze Garden)'),
            ),
            onPressed: () {
              setState(() {
                _kasaBakiyesi += _birikimHavuzu;
                _birikimHavuzu = 0;
                _bahceCurudu = true;
              });
              _verileriKaydet();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    final sayfalar = [
      _buildAnaSeraVeKasaSayfasi(),
      _buildIhtiyaclarSayfasi(),
      _buildWishSayfasi(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final genisEkran = constraints.maxWidth >= 750;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E1C19),
            title: const Row(
              children: [
                Icon(Icons.spa_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'SERA FİNANS',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 17),
                  ),
                ),
                SizedBox(width: 6),
                Chip(
                  label: Text('CFO', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
                  backgroundColor: Color(0xFF1D332E),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              // DİL DEĞİŞTİRME BUTONU (TR / EN)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                    side: const BorderSide(color: Color(0xFF284B43)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _diliDegistir,
                  child: Text(
                    _ingilizceMi ? 'TR' : 'EN',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
              IconButton(
                tooltip: _t('Su & Bildirim Ayarları', 'Water & Alert Settings'),
                icon: Icon(
                  _suHatirlaticiAktif ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                  color: _suHatirlaticiAktif ? const Color(0xFF38BDF8) : Colors.white54,
                ),
                onPressed: _suAyarlariDialog,
              ),
              IconButton(
                tooltip: _t('Temiz Başlangıç (Tümünü Sıfırla)', 'Clean Slate (Reset All)'),
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white54),
                onPressed: _tumVerileriSifirlaDialog,
              ),
            ],
          ),
          body: Row(
            children: [
              if (genisEkran)
                NavigationRail(
                  backgroundColor: const Color(0xFF0E1C19),
                  selectedIndex: _seciliSekme,
                  onDestinationSelected: (i) => setState(() => _seciliSekme = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.yard_outlined),
                      selectedIcon: const Icon(Icons.yard_rounded),
                      label: Text(_t('Sera & Kasa', 'Greenhouse')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.checklist_rtl_outlined),
                      selectedIcon: const Icon(Icons.checklist_rtl_rounded),
                      label: Text(_t('İhtiyaçlar', 'Fixed Needs')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.photo_library_outlined),
                      selectedIcon: const Icon(Icons.photo_library_rounded),
                      label: Text(_t('Wish Albüm', 'Wish Album')),
                    ),
                  ],
                ),
              Expanded(child: sayfalar[_seciliSekme]),
            ],
          ),
          bottomNavigationBar: genisEkran
              ? null
              : NavigationBar(
                  backgroundColor: const Color(0xFF0E1C19),
                  selectedIndex: _seciliSekme,
                  onDestinationSelected: (i) => setState(() => _seciliSekme = i),
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.yard_rounded),
                      label: _t('Sera & Kasa', 'Greenhouse'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.checklist_rtl_rounded),
                      label: _t('İhtiyaçlar', 'Fixed Needs'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.photo_library_rounded),
                      label: _t('Wish Albüm', 'Wish Album'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  // --- ANA EKRAN ---
  Widget _buildAnaSeraVeKasaSayfasi() {
    final kalanGunluk = (_gunlukGuvenliLimit - _bugunHarcanan).clamp(0.0, double.infinity);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCanliBotanikBahceKarti(),
        const SizedBox(height: 12),

        _buildGunlukSuKarti(),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _miniMetrikKart(
                baslik: _t('Nakit Kasa', 'Cash Vault'),
                deger: '₺${_kasaBakiyesi.toStringAsFixed(2)}',
                altBilgi: 'Net: ₺${_harcanabilirNetBakiye.toStringAsFixed(0)}',
                ikon: Icons.account_balance_wallet_rounded,
                renk: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _paraGelisGunuSecDialog,
                borderRadius: BorderRadius.circular(18),
                child: _miniMetrikKart(
                  baslik: _t('Bugünkü Limit', 'Today\'s Limit'),
                  deger: '₺${kalanGunluk.toStringAsFixed(2)}',
                  altBilgi: _t(
                    'Ayın $_paraGelisGunu\'ine $_gelirGununeKalanGun gün ✎',
                    '$_gelirGununeKalanGun d to day $_paraGelisGunu ✎',
                  ),
                  ikon: Icons.event_repeat_rounded,
                  renk: _limitAsildiMi ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _islemEkleDialog(true),
                icon: const Icon(Icons.add_circle_rounded, size: 19),
                label: Text(
                  _t('Gelir Ekle', 'Income'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  foregroundColor: const Color(0xFF10B981),
                ),
                onPressed: _sabitGelirYonetDialog,
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: Text(
                  _t('Sabitler', 'Presets'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: const Color(0xFF1F3833),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _islemEkleDialog(false),
                icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFF59E0B), size: 19),
                label: Text(
                  _t('Harcama', 'Expense'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),

        if (_sabitGelirler.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sabitGelirler.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final sg = _sabitGelirler[index];
                return ActionChip(
                  avatar: const Icon(Icons.flash_on_rounded, size: 15, color: Color(0xFFF59E0B)),
                  backgroundColor: const Color(0xFF142B26),
                  side: const BorderSide(color: Color(0xFF284B43)),
                  label: Text(
                    '${sg.ad} +₺${sg.tutar.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _sabitGelirUygula(sg),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 14),

        Card(
          color: _limitAsildiMi || _bahceCurudu
              ? const Color(0xFF2E1618)
              : const Color(0xFF142B26),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _limitAsildiMi || _bahceCurudu
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFF59E0B),
                  child: const Icon(Icons.support_agent_rounded, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('ÖZEL FİNANS DİREKTÖRÜ (CFO)', 'PERSONAL CHIEF FINANCIAL OFFICER (CFO)'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cfoMesaji,
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _t('Kuruşu Kuruşuna İşlemler', 'Penny-by-Penny Ledger'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _t(
                'Kurtarılan: ₺${_kurtarilanPara.toStringAsFixed(0)}',
                'Saved: ₺${_kurtarilanPara.toStringAsFixed(0)}',
              ),
              style: const TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_islemler.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                _t(
                  'Henüz işlem kaydı yok. Gelir veya harcama ekleyerek başlayabilirsin.',
                  'No transactions logged yet. Add an income or expense to begin.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          )
        else
          ..._islemler.map(
            (islem) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: islem.gelirMi
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFFEF4444).withValues(alpha: 0.15),
                  child: Icon(
                    islem.gelirMi ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    size: 18,
                    color: islem.gelirMi ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                title: Text(islem.baslik, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(_kategoriEtiketi(islem.kategori), style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  '${islem.gelirMi ? '+' : '-'}₺${islem.tutar.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: islem.gelirMi ? const Color(0xFF10B981) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- GÜNLÜK SU & SERA NEMİ KARTI ---
  Widget _buildGunlukSuKarti() {
    final litreIcilen = (_icilenSuMl / 1000).toStringAsFixed(2);
    final litreHedef = (_gunlukSuHedefiMl / 1000).toStringAsFixed(2);
    final hedefTamam = _icilenSuMl >= _gunlukSuHedefiMl;

    return Card(
      color: const Color(0xFF11262A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: hedefTamam
              ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
              : const Color(0xFF1E3F47),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.water_drop_rounded, color: Color(0xFF38BDF8), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _t('Günlük Su & Sera Nemi', 'Daily Water & Dew'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(%${(_suTamamlanmaOrani * 100).toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$litreIcilen / $litreHedef L • ${_suHatirlaticiAktif ? _t("$_suHatirlatmaAraligiSaat sa. bir uyarı", "Every ${_suHatirlatmaAraligiSaat}h") : _t("Uyarı kapalı", "Alerts off")}',
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _suTamamlanmaOrani,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.black38,
                    color: const Color(0xFF38BDF8),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_icilenSuMl >= 250)
              IconButton(
                tooltip: _t('1 Bardak Geri Al', 'Undo 1 Glass'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 19, color: Colors.white54),
                onPressed: () => _suEkle(-250),
              ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                foregroundColor: const Color(0xFF38BDF8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: Size.zero,
              ),
              onPressed: () => _suEkle(250),
              child: const Text('+250 ml', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            IconButton(
              tooltip: _t('Su & Bildirim Ayarları', 'Water & Alert Settings'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.tune_rounded, size: 18, color: Colors.white70),
              onPressed: _suAyarlariDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanliBotanikBahceKarti() {
    final int canliOgeSayisi = _bahceCurudu ? 0 : (_birikimHavuzu / 100).floor();
    final Color aktifRenk = _bahceCurudu
        ? const Color(0xFF9CA3AF)
        : (_limitAsildiMi ? Colors.orangeAccent : const Color(0xFF10B981));

    String ekosistemDurumu;
    if (_bahceCurudu) {
      ekosistemDurumu = _t('Kırağı Yemiş Toprak', 'Frostbitten Soil');
    } else if (_limitAsildiMi) {
      ekosistemDurumu = _t('Susuz • Yapraklar Solgun', 'Dehydrated • Wilting Leaves');
    } else if (canliOgeSayisi == 0) {
      ekosistemDurumu = _t('Taze Ekilmiş Sera Toprağı', 'Freshly Seeded Greenhouse');
    } else if (canliOgeSayisi < 10) {
      ekosistemDurumu = _t('Filizlenen Botanik Bahçe', 'Sprouting Botanical Garden');
    } else if (canliOgeSayisi < 30) {
      ekosistemDurumu = _t('Gelişen Egzotik Ekosistem', 'Thriving Exotic Ecosystem');
    } else if (canliOgeSayisi < 80) {
      ekosistemDurumu = _t('Biyolüminesans Yağmur Ormanı', 'Bioluminescent Rainforest');
    } else {
      ekosistemDurumu = _t('Kadim Zümrüt Cenneti', 'Ancient Emerald Sanctuary');
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF0A1916),
        border: Border.all(color: aktifRenk.withValues(alpha: 0.45), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 255,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GercekciBotanikBahceRessami(
                      birikim: _birikimHavuzu,
                      curudu: _bahceCurudu,
                      susuz: _limitAsildiMi,
                      suOrani: _suTamamlanmaOrani,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: aktifRenk.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ekosistemDurumu,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: aktifRenk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _bahceCurudu
                              ? _t('Canlandırmak için ₺100+ ekle', 'Add ₺100+ to revive')
                              : _t(
                                  '$canliOgeSayisi Canlı Flora • Nem %${(_suTamamlanmaOrani * 100).toStringAsFixed(0)}',
                                  '$canliOgeSayisi Live Flora • Dew %${(_suTamamlanmaOrani * 100).toStringAsFixed(0)}',
                                ),
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _t('BİRİKİM HAVUZU', 'SAVINGS POOL'),
                          style: const TextStyle(fontSize: 9, color: Colors.white60),
                        ),
                        Text(
                          '₺${_birikimHavuzu.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF34D399),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _birikimeAktarDialog,
                    icon: const Icon(Icons.water_drop_rounded, size: 18),
                    label: Text(
                      _t('Bahçeye Para At (+₺100)', 'Feed Garden (+₺100)'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: _birikimiBozDialog,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Color(0xFFEF4444)),
                  label: Text(_t('Sıfırla', 'Reset'), style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniMetrikKart({
    required String baslik,
    required String deger,
    required String altBilgi,
    required IconData ikon,
    required Color renk,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(baslik, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Icon(ikon, color: renk, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              deger,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: renk),
            ),
            const SizedBox(height: 2),
            Text(altBilgi, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
      ),
    );
  }

  // --- SEKME 2: SABİT İHTİYAÇLAR ---
  Widget _buildIhtiyaclarSayfasi() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('Kilitli İhtiyaç Rezervi', 'Locked Needs Reserve'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₺${_odenmemisIhtiyacToplami.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _yeniIhtiyacEkleDialog,
                  icon: const Icon(Icons.add),
                  label: Text(_t('İhtiyaç Ekle', 'Add Need')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_ihtiyaclar.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Center(
              child: Text(
                _t(
                  'Henüz zorunlu ihtiyaç eklenmedi. Yurt, fatura, erzak gibi giderleri buraya ekleyebilirsin.',
                  'No fixed expenses added yet. Add rent, bills, or groceries here to lock their budget.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ..._ihtiyaclar.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: CheckboxListTile(
              value: item.odendi,
              activeColor: const Color(0xFF10B981),
              secondary: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                onPressed: () {
                  setState(() => _ihtiyaclar.remove(item));
                  _verileriKaydet();
                },
              ),
              title: Text(
                item.ad,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration: item.odendi ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                _t(
                  'Durum: ${item.sonGun} • Tutar: ₺${item.tutar.toStringAsFixed(2)}',
                  'Due: ${item.sonGun} • Amount: ₺${item.tutar.toStringAsFixed(2)}',
                ),
              ),
              onChanged: (val) {
                setState(() {
                  item.odendi = val ?? false;
                  if (item.odendi && _kasaBakiyesi >= item.tutar) {
                    _kasaBakiyesi -= item.tutar;
                    _islemler.insert(
                      0,
                      Islem(
                        baslik: '${_t("İhtiyaç Ödemesi", "Bill Paid")}: ${item.ad}',
                        tutar: item.tutar,
                        gelirMi: false,
                        kategori: 'Zorunlu İhtiyaç',
                        tarih: DateTime.now(),
                      ),
                    );
                  }
                });
                _verileriKaydet();
              },
            ),
          ),
        ),
      ],
    );
  }

  void _yeniIhtiyacEkleDialog() {
    final adCtrl = TextEditingController();
    final tutarCtrl = TextEditingController();
    final zamanCtrl = TextEditingController(text: _t('Bu ay', 'This month'));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(_t('Yeni Zorunlu İhtiyaç Tanımla', 'Add Fixed Expense')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: adCtrl,
              decoration: InputDecoration(
                labelText: _t('İhtiyaç Adı (Örn: Erzak)', 'Expense Name (e.g. Groceries)'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _t('Tahmini Tutar (₺)', 'Estimated Amount (₺)'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: zamanCtrl,
              decoration: InputDecoration(
                labelText: _t('Hatırlatma Zamanı', 'Due Date / Note'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('İptal', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final tutar = double.tryParse(tutarCtrl.text.replaceAll(',', '.')) ?? 0;
              if (adCtrl.text.trim().isEmpty || tutar <= 0) return;
              setState(() {
                _ihtiyaclar.add(
                  SabitIhtiyac(
                    ad: adCtrl.text.trim(),
                    tutar: tutar,
                    sonGun: zamanCtrl.text.trim().isEmpty ? _t('Bu ay', 'This month') : zamanCtrl.text.trim(),
                  ),
                );
              });
              _verileriKaydet();
              Navigator.pop(ctx);
            },
            child: Text(_t('Ekle', 'Add')),
          ),
        ],
      ),
    );
  }

  // --- SEKME 3: WISH (KEYFİ İSTEKLER) ALBÜMÜ ---
  Future<void> _mevcutKartaSsEkle(WishUrun urun) async {
    final XFile? secilen = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (secilen != null) {
      final kaliciYol = await _gorseliKaliciKopyala(secilen.path);
      setState(() {
        urun.gorselYolu = kaliciYol;
      });
      _verileriKaydet();
    }
  }

  void _wishSatinAlindi(WishUrun urun) {
    if (_kasaBakiyesi < urun.fiyat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            _t(
              'Kasada yeterli bakiye yok Sayın Kurucu! (${urun.ad}: ₺${urun.fiyat.toStringAsFixed(0)}, Kasa: ₺${_kasaBakiyesi.toStringAsFixed(0)})',
              'Insufficient vault balance, Founder! (${urun.ad}: ₺${urun.fiyat.toStringAsFixed(0)}, Vault: ₺${_kasaBakiyesi.toStringAsFixed(0)})',
            ),
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162925),
        title: Text(_t('Satın Almayı Onayla', 'Confirm Purchase')),
        content: Text(
          _t(
            '${urun.ad} için ₺${urun.fiyat.toStringAsFixed(2)} nakit kasadan düşülüp harcamalara eklensin mi?',
            'Deduct ₺${urun.fiyat.toStringAsFixed(2)} for ${urun.ad} from your cash vault and log as an expense?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Vazgeç', 'Cancel'))),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.shopping_bag_rounded, size: 18),
            label: Text(_t('Aldım, Kasadan Düş', 'Bought, Deduct Cash')),
            onPressed: () {
              setState(() {
                _gunKontrolEt();
                _kasaBakiyesi -= urun.fiyat;
                _bugunHarcanan += urun.fiyat;
                _islemler.insert(
                  0,
                  Islem(
                    baslik: '${_t("Wish Alındı", "Wish Bought")}: ${urun.ad}',
                    tutar: urun.fiyat,
                    gelirMi: false,
                    kategori: 'Keyfi Alışveriş',
                    tarih: DateTime.now(),
                  ),
                );
                _wishListesi.remove(urun);
              });
              _verileriKaydet();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      'Hayırlı olsun! ₺${urun.fiyat.toStringAsFixed(0)} kasadan düşüldü.',
                      'Enjoy! ₺${urun.fiyat.toStringAsFixed(0)} deducted from your vault.',
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _gorseliTamEkranAc(String yol, String baslik) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.file(File(yol), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black87),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWishSayfasi() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Keyfi İstek Panosu (SS Albümü)', 'Impulse Wishlist (SS Album)'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _t(
                      'Alırsan kasadan düşer, vazgeçersen bahçeye gübre olur',
                      'Buying deducts cash; skipping fertilizes your garden',
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _yeniWishEkleDialog,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: Text(_t('SS & İstek Ekle', 'Add Wish')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_wishListesi.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _t(
                  'İstek listesi boş. Sağ üstten SS ve ürün ekleyebilirsin.',
                  'Wishlist is empty. Tap above to add screenshots and items.',
                ),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ..._wishListesi.map((urun) {
          final oran = urun.fiyat > 0 ? (_harcanabilirNetBakiye / urun.fiyat).clamp(0.0, 1.0) : 0.0;
          final gorselVarMi = urun.gorselYolu != null && File(urun.gorselYolu!).existsSync();

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (gorselVarMi)
                  GestureDetector(
                    onTap: () => _gorseliTamEkranAc(urun.gorselYolu!, urun.ad),
                    child: Stack(
                      children: [
                        SizedBox(
                          height: 185,
                          width: double.infinity,
                          child: Image.file(
                            File(urun.gorselYolu!),
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            children: [
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                onPressed: () => _mevcutKartaSsEkle(urun),
                                icon: const Icon(Icons.edit_rounded, size: 15),
                                label: Text(_t('SS Değiştir', 'Change SS'), style: const TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.7),
                                ),
                                tooltip: _t('Listeden Sil', 'Remove'),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                onPressed: () {
                                  setState(() => _wishListesi.remove(urun));
                                  _verileriKaydet();
                                },
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(
                                  _t('Büyütmek için dokun', 'Tap to zoom'),
                                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Stack(
                    children: [
                      InkWell(
                        onTap: () => _mevcutKartaSsEkle(urun),
                        child: Container(
                          height: 105,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: urun.renk.withValues(alpha: 0.08),
                            border: const Border(bottom: BorderSide(color: Color(0xFF233E38))),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, color: urun.renk, size: 30),
                              const SizedBox(height: 6),
                              Text(
                                _t(
                                  'Bu istek için ekran görüntüsü (SS) seçmek üzere dokun',
                                  'Tap to attach a screenshot (SS) for this wish',
                                ),
                                style: TextStyle(fontSize: 12, color: urun.renk, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          tooltip: _t('Listeden Sil', 'Remove'),
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
                          onPressed: () {
                            setState(() => _wishListesi.remove(urun));
                            _verileriKaydet();
                          },
                        ),
                      ),
                    ],
                  ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(urun.ad, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(urun.not, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                              ],
                            ),
                          ),
                          Text(
                            '₺${urun.fiyat.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _t('Keyfi Bütçe Karşılama Oranı', 'Discretionary Budget Coverage'),
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                          Text(
                            '%${(oran * 100).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: oran >= 1.0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: oran,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(6),
                        backgroundColor: Colors.white12,
                        color: oran >= 1.0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              icon: const Icon(Icons.shopping_bag_rounded, size: 17),
                              label: Text(
                                _t('Aldım (Kasadan Düş)', 'Bought (Deduct)'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              onPressed: () => _wishSatinAlindi(urun),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              icon: const Icon(Icons.spa_rounded, color: Color(0xFF10B981), size: 17),
                              label: Text(_t('Vazgeçtim, Göm', 'Skip & Bury'), style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _kurtarilanPara += urun.fiyat;
                                  _birikimHavuzu += (urun.fiyat * 0.25);
                                  _bahceCurudu = false;
                                  _wishListesi.remove(urun);
                                });
                                _verileriKaydet();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        'Harika disiplin! ${urun.ad} almaktan vazgeçtin, bahçeye ₺${(urun.fiyat * 0.25).toStringAsFixed(0)} ödül gübresi eklendi!',
                                        'Great discipline! You skipped ${urun.ad}, adding ₺${(urun.fiyat * 0.25).toStringAsFixed(0)} bonus fertilizer to your garden!',
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _yeniWishEkleDialog() {
    final adCtrl = TextEditingController();
    final fiyatCtrl = TextEditingController();
    final notCtrl = TextEditingController();
    String? secilenGorselYolu;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF162925),
          title: Text(_t('Albüme Yeni SS & İstek Ekle', 'Add Screenshot & Wish')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    final XFile? dosya = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (dosya != null) {
                      final kaliciYol = await _gorseliKaliciKopyala(dosya.path);
                      setDialogState(() {
                        secilenGorselYolu = kaliciYol;
                      });
                    }
                  },
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1C19),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: secilenGorselYolu != null
                        ? Image.file(File(secilenGorselYolu!), fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF10B981), size: 36),
                              const SizedBox(height: 8),
                              Text(
                                _t(
                                  'Galeriden Ekran Görüntüsü (SS) Seç',
                                  'Pick Screenshot (SS) from Gallery',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adCtrl,
                  decoration: InputDecoration(labelText: _t('Ürün Adı', 'Item Name')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fiyatCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: _t('Fiyatı (₺)', 'Price (₺)')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notCtrl,
                  decoration: InputDecoration(labelText: _t('Not (Örn: Trendyol SS)', 'Note (e.g. Store SS)')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('İptal', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final fiyat = double.tryParse(fiyatCtrl.text.replaceAll(',', '.')) ?? 0;
                if (adCtrl.text.trim().isEmpty || fiyat <= 0) return;
                setState(() {
                  _wishListesi.add(
                    WishUrun(
                      ad: adCtrl.text.trim(),
                      fiyat: fiyat,
                      not: notCtrl.text.trim().isEmpty
                          ? _t('Keyfi istek', 'Wishlist item')
                          : notCtrl.text.trim(),
                      gorselYolu: secilenGorselYolu,
                    ),
                  );
                });
                _verileriKaydet();
                Navigator.pop(ctx);
              },
              child: Text(_t('Albüme Koy', 'Add to Album')),
            ),
          ],
        ),
      ),
    );
  }
}

// --- GERÇEKÇİ DİJİTAL BOTANİK İLLÜSTRASYON RESSAMI (SU NEMİ + HER 100 TL = +1 YAŞAM) ---
class GercekciBotanikBahceRessami extends CustomPainter {
  final double birikim;
  final bool curudu;
  final bool susuz;
  final double suOrani;

  GercekciBotanikBahceRessami({
    required this.birikim,
    required this.curudu,
    required this.susuz,
    required this.suOrani,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final groundY = size.height * 0.76;
    final int adim = curudu ? 0 : (birikim / 100).floor();
    final double yogunluk = curudu ? 0.0 : (birikim / 15000.0).clamp(0.0, 1.0);

    final List<Color> skyColors;
    if (curudu) {
      skyColors = [const Color(0xFF14161A), const Color(0xFF23272F), const Color(0xFF1B1E24)];
    } else if (susuz) {
      skyColors = [const Color(0xFF1F1209), const Color(0xFF3E2212), const Color(0xFF522E16)];
    } else if (suOrani >= 1.0) {
      skyColors = [const Color(0xFF04171B), const Color(0xFF0B3538), const Color(0xFF13524A)];
    } else {
      skyColors = [const Color(0xFF041210), const Color(0xFF0B2B25), const Color(0xFF15473C)];
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: skyColors,
        ).createShader(rect),
    );

    final isikMerkezi = Offset(size.width * 0.5, size.height * 0.14);
    final isikRengi = curudu
        ? const Color(0xFF6B7280)
        : (susuz
            ? const Color(0xFFF59E0B)
            : (suOrani >= 1.0 ? const Color(0xFF38BDF8) : const Color(0xFF6EE7B7)));

    canvas.drawCircle(
      isikMerkezi,
      size.width * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [
            isikRengi.withValues(alpha: curudu ? 0.08 : 0.24),
            isikRengi.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: isikMerkezi, radius: size.width * 0.42)),
    );

    if (!curudu) {
      for (int r = -1; r <= 1; r++) {
        final rayPath = Path()
          ..moveTo(isikMerkezi.dx + r * 28, 0)
          ..lineTo(isikMerkezi.dx + r * 28 + 36, 0)
          ..lineTo(size.width * (0.5 + r * 0.28) + 70, groundY)
          ..lineTo(size.width * (0.5 + r * 0.28) - 40, groundY)
          ..close();

        canvas.drawPath(
          rayPath,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                isikRengi.withValues(alpha: 0.07 + yogunluk * 0.05),
                Colors.transparent,
              ],
            ).createShader(rect),
        );
      }
    }

    final kemerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08 + suOrani * 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (int i = 1; i <= 3; i++) {
      final archRect = Rect.fromCenter(
        center: Offset(size.width * 0.5, groundY + 18),
        width: size.width * (0.48 + i * 0.21),
        height: size.height * (0.95 + i * 0.24),
      );
      canvas.drawArc(archRect, math.pi, math.pi, false, kemerPaint);
    }

    _cizArkaPlanOrmanSilueti(canvas, size, groundY, curudu, susuz);

    final tepePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: curudu
            ? [const Color(0xFF23272F), const Color(0xFF16181D)]
            : (susuz
                ? [const Color(0xFF452715), const Color(0xFF29160B)]
                : [const Color(0xFF0E352C), const Color(0xFF08211B)]),
      ).createShader(Rect.fromLTWH(0, groundY - 45, size.width, 50));

    final tepePath = Path()
      ..moveTo(0, groundY)
      ..cubicTo(
        size.width * 0.22,
        groundY - 42,
        size.width * 0.42,
        groundY - 8,
        size.width * 0.65,
        groundY - 26,
      )
      ..cubicTo(
        size.width * 0.82,
        groundY - 38,
        size.width * 0.92,
        groundY - 14,
        size.width,
        groundY - 22,
      )
      ..lineTo(size.width, groundY)
      ..close();
    canvas.drawPath(tepePath, tepePaint);

    _cizToprakVeKokAgi(canvas, size, groundY, adim, curudu, susuz);

    if (!curudu && adim >= 3) {
      final goletGenislik = (58.0 + (adim * 1.4)).clamp(58.0, 125.0);
      _cizYansimaliGolet(canvas, Offset(size.width * 0.82, groundY + 13), goletGenislik, adim, susuz);
    }

    if (curudu) {
      _cizCurumusAgac(canvas, Offset(size.width * 0.48, groundY));
      return;
    }

    _cizGercekciCimler(canvas, size, groundY, adim, susuz);

    final rng = math.Random(1453);
    final int gosterilecekOge = math.min(adim, 140);

    if (adim >= 10) {
      _cizSarkanSarmasiklar(canvas, size, groundY, adim, susuz);
    }

    for (int i = 0; i < gosterilecekOge; i++) {
      double normX = rng.nextDouble();
      if ((normX - 0.48).abs() < 0.06) {
        normX = normX < 0.48 ? normX - 0.08 : normX + 0.08;
      }
      final double x = (normX.clamp(0.05, 0.95)) * size.width;
      final double olcek = (0.65 + rng.nextDouble() * 0.55) * (1.0 + (adim - i) * 0.008).clamp(1.0, 1.35);
      final int tur = i % 5;

      if (tur == 0) {
        _cizEgreltiOtu(canvas, Offset(x, groundY), olcek, susuz);
      } else if (tur == 1) {
        final cicekRenkler = [
          const Color(0xFFF472B6),
          const Color(0xFFC084FC),
          const Color(0xFF38BDF8),
          const Color(0xFFFBBF24),
        ];
        _cizEgzotikCicek(canvas, Offset(x, groundY), olcek, cicekRenkler[i % cicekRenkler.length], susuz);
      } else if (tur == 2) {
        _cizBiyoluminesansMantar(canvas, Offset(x, groundY), olcek, susuz);
      } else if (tur == 3) {
        _cizKristalVeYosunTasi(canvas, Offset(x, groundY), olcek, susuz);
      } else {
        final fy = groundY - 18 - rng.nextDouble() * (groundY - 35);
        _cizAtesBocegi(canvas, Offset(x, fy), susuz);
      }
    }

    _cizOrganikKahramanAgac(canvas, Offset(size.width * 0.48, groundY), birikim, adim, susuz);

    if (suOrani > 0) {
      _cizSeraNemPariltilari(canvas, size, groundY, suOrani);
    }
  }

  void _cizSeraNemPariltilari(Canvas canvas, Size size, double groundY, double suOrani) {
    final int damlaSayisi = (suOrani * 28).round();
    final suRng = math.Random(404);
    for (int d = 0; d < damlaSayisi; d++) {
      final dx = suRng.nextDouble() * size.width;
      final dy = 16.0 + suRng.nextDouble() * (groundY - 24);
      final r = 1.5 + suRng.nextDouble() * 2.2;

      canvas.drawCircle(
        Offset(dx, dy),
        r * 3.2,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        Offset(dx, dy),
        r,
        Paint()..color = const Color(0xFFBAE6FD).withValues(alpha: 0.85),
      );
    }
  }

  void _cizArkaPlanOrmanSilueti(Canvas canvas, Size size, double groundY, bool curudu, bool susuz) {
    final siluetPaint = Paint()
      ..color = curudu
          ? const Color(0xFF1B1E24)
          : (susuz ? const Color(0xFF2E190E) : const Color(0xFF0A241E))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final rng = math.Random(99);
    for (int i = 0; i < 14; i++) {
      final bx = (i / 13.0) * size.width;
      final bh = 35.0 + rng.nextDouble() * 48.0;
      final bw = 28.0 + rng.nextDouble() * 32.0;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(bx, groundY - bh * 0.4), width: bw, height: bh),
        siluetPaint,
      );
    }
  }

  void _cizToprakVeKokAgi(Canvas canvas, Size size, double groundY, int adim, bool curudu, bool susuz) {
    final soilRect = Rect.fromLTWH(0, groundY, size.width, size.height - groundY);
    canvas.drawRect(
      soilRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: curudu
              ? [const Color(0xFF282B33), const Color(0xFF15171C)]
              : [const Color(0xFF241710), const Color(0xFF110A07)],
        ).createShader(soilRect),
    );

    final rng = math.Random(77);
    final tasPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (int i = 0; i < 18; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = groundY + 10 + rng.nextDouble() * (size.height - groundY - 14);
      canvas.drawOval(Rect.fromCenter(center: Offset(sx, sy), width: 7 + rng.nextDouble() * 8, height: 4), tasPaint);
    }

    if (!curudu && adim > 0) {
      final kokRenk = susuz ? const Color(0xFFD97706) : const Color(0xFF10B981);
      final kokPaint = Paint()
        ..color = kokRenk.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      final kokSayisi = math.min(2 + (adim ~/ 2), 18);
      final merkezX = size.width * 0.48;
      for (int k = 0; k < kokSayisi; k++) {
        final yon = (k % 2 == 0 ? 1 : -1) * (0.2 + (k / kokSayisi));
        final uzunluk = (18.0 + adim * 0.9).clamp(18.0, size.height - groundY - 6);
        final path = Path()
          ..moveTo(merkezX, groundY + 2)
          ..quadraticBezierTo(
            merkezX + yon * 45,
            groundY + uzunluk * 0.5,
            merkezX + yon * (70 + k * 6),
            groundY + uzunluk,
          );
        canvas.drawPath(path, kokPaint);
      }
    }

    final turfColor = curudu
        ? const Color(0xFF4B5563)
        : (susuz ? const Color(0xFFB45309) : const Color(0xFF059669));
    canvas.drawRect(
      Rect.fromLTWH(0, groundY - 3, size.width, 6),
      Paint()
        ..shader = LinearGradient(
          colors: [
            turfColor.withValues(alpha: 0.8),
            curudu ? const Color(0xFF6B7280) : const Color(0xFF34D399),
            turfColor.withValues(alpha: 0.8),
          ],
        ).createShader(Rect.fromLTWH(0, groundY - 3, size.width, 6)),
    );
  }

  void _cizGercekciCimler(Canvas canvas, Size size, double groundY, int adim, bool susuz) {
    final int cimAdedi = (28 + adim * 2).clamp(28, 160);
    final rng = math.Random(321);
    final baseColor = susuz ? const Color(0xFFD97706) : const Color(0xFF10B981);
    final tipColor = susuz ? const Color(0xFFFBBF24) : const Color(0xFF6EE7B7);

    for (int i = 0; i < cimAdedi; i++) {
      final x = rng.nextDouble() * size.width;
      final h = (7.0 + rng.nextDouble() * 11.0) * (susuz ? 0.75 : 1.0);
      final egim = (rng.nextDouble() - 0.5) * 10.0;

      final paint = Paint()
        ..color = Color.lerp(baseColor, tipColor, rng.nextDouble())!.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(x, groundY)
        ..quadraticBezierTo(x + egim * 0.4, groundY - h * 0.6, x + egim, groundY - h);
      canvas.drawPath(path, paint);
    }
  }

  void _cizEgreltiOtu(Canvas canvas, Offset kok, double olcek, bool susuz) {
    final anaRenk = susuz ? const Color(0xFFD97706) : const Color(0xFF059669);
    final acikRenk = susuz ? const Color(0xFFFBBF24) : const Color(0xFF34D399);

    for (int dal = -2; dal <= 2; dal++) {
      final aci = dal * 0.36;
      final uzunluk = (26.0 - dal.abs() * 3.0) * olcek;
      final uc = Offset(
        kok.dx + math.sin(aci) * uzunluk * 1.15,
        kok.dy - math.cos(aci) * uzunluk * (susuz ? 0.75 : 1.0),
      );

      final path = Path()
        ..moveTo(kok.dx, kok.dy)
        ..quadraticBezierTo(
          kok.dx + math.sin(aci) * uzunluk * 0.5,
          kok.dy - uzunluk * 0.8,
          uc.dx,
          uc.dy,
        );

      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(anaRenk, acikRenk, (dal + 2) / 4)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * olcek
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _cizEgzotikCicek(Canvas canvas, Offset kok, double olcek, Color renk, bool susuz) {
    final sapRenk = susuz ? const Color(0xFFB45309) : const Color(0xFF10B981);
    final boy = (22.0 + olcek * 14.0) * (susuz ? 0.8 : 1.0);
    final tepe = Offset(kok.dx + (susuz ? 5 : 2), kok.dy - boy);

    canvas.drawPath(
      Path()
        ..moveTo(kok.dx, kok.dy)
        ..quadraticBezierTo(kok.dx - 3, kok.dy - boy * 0.5, tepe.dx, tepe.dy),
      Paint()
        ..color = sapRenk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    final cicekRenk = susuz ? const Color(0xFFF59E0B) : renk;
    canvas.drawCircle(
      tepe,
      11 * olcek,
      Paint()
        ..color = cicekRenk.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    for (int p = 0; p < 5; p++) {
      final a = (p * 2 * math.pi) / 5;
      final px = tepe.dx + math.cos(a) * 5.2 * olcek;
      final py = tepe.dy + math.sin(a) * 5.2 * olcek;
      canvas.drawCircle(Offset(px, py), 3.6 * olcek, Paint()..color = cicekRenk);
    }
    canvas.drawCircle(tepe, 2.4 * olcek, Paint()..color = const Color(0xFFFDE047));
  }

  void _cizBiyoluminesansMantar(Canvas canvas, Offset kok, double olcek, bool susuz) {
    final capColor = susuz ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);
    final h = 18.0 * olcek;

    canvas.drawPath(
      Path()
        ..moveTo(kok.dx, kok.dy)
        ..quadraticBezierTo(kok.dx - 2, kok.dy - h * 0.5, kok.dx + 1, kok.dy - h),
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 * olcek
        ..strokeCap = StrokeCap.round,
    );

    final capCenter = Offset(kok.dx + 1, kok.dy - h);
    canvas.drawCircle(
      capCenter,
      14 * olcek,
      Paint()
        ..color = capColor.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    canvas.drawArc(
      Rect.fromCenter(center: capCenter, width: 20 * olcek, height: 15 * olcek),
      math.pi,
      math.pi,
      true,
      Paint()..color = capColor,
    );
  }

  void _cizKristalVeYosunTasi(Canvas canvas, Offset kok, double olcek, bool susuz) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(kok.dx, kok.dy - 3), width: 18 * olcek, height: 9 * olcek),
      Paint()..color = const Color(0xFF334155),
    );

    final kristalRenk = susuz ? const Color(0xFFFBBF24) : const Color(0xFF6EE7B7);
    final kPath = Path()
      ..moveTo(kok.dx + 3, kok.dy - 2)
      ..lineTo(kok.dx + 7 * olcek, kok.dy - 16 * olcek)
      ..lineTo(kok.dx + 11 * olcek, kok.dy - 2)
      ..close();
    canvas.drawPath(kPath, Paint()..color = kristalRenk.withValues(alpha: 0.85));
  }

  void _cizYansimaliGolet(Canvas canvas, Offset merkez, double genislik, int adim, bool susuz) {
    final suRenk = susuz ? const Color(0xFFB45309) : const Color(0xFF06B6D4);
    final pondRect = Rect.fromCenter(center: merkez, width: genislik, height: 16);

    canvas.drawOval(
      pondRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            suRenk.withValues(alpha: 0.75),
            const Color(0xFF083344).withValues(alpha: 0.9),
          ],
        ).createShader(pondRect),
    );

    canvas.drawLine(
      Offset(merkez.dx - genislik * 0.25, merkez.dy - 2),
      Offset(merkez.dx + genislik * 0.2, merkez.dy - 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );

    if (adim >= 6) {
      canvas.drawCircle(Offset(merkez.dx - 10, merkez.dy - 2), 4.5, Paint()..color = const Color(0xFFF472B6));
      canvas.drawCircle(Offset(merkez.dx - 10, merkez.dy - 2), 1.8, Paint()..color = const Color(0xFFFDE047));
    }
    if (adim >= 15) {
      canvas.drawCircle(Offset(merkez.dx + 14, merkez.dy + 1), 4.0, Paint()..color = const Color(0xFFC084FC));
    }
  }

  void _cizSarkanSarmasiklar(Canvas canvas, Size size, double groundY, int adim, bool susuz) {
    final sarmasikSayisi = math.min((adim - 8) ~/ 2, 14);
    final rng = math.Random(888);
    final yaprakRenk = susuz ? const Color(0xFFD97706) : const Color(0xFF10B981);
    final cicekRenk = susuz ? const Color(0xFFFBBF24) : const Color(0xFFE879F9);

    for (int s = 0; s < sarmasikSayisi; s++) {
      final sx = 24.0 + rng.nextDouble() * (size.width - 48.0);
      final uzunluk = 28.0 + rng.nextDouble() * 52.0;

      final vinePath = Path()
        ..moveTo(sx, 0)
        ..quadraticBezierTo(sx + 8, uzunluk * 0.5, sx - 4, uzunluk);

      canvas.drawPath(
        vinePath,
        Paint()
          ..color = yaprakRenk.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      canvas.drawCircle(
        Offset(sx - 4, uzunluk),
        3.2,
        Paint()..color = cicekRenk.withValues(alpha: 0.85),
      );
    }
  }

  void _cizAtesBocegi(Canvas canvas, Offset pos, bool susuz) {
    final renk = susuz ? Colors.orangeAccent : const Color(0xFFFDE047);
    canvas.drawCircle(
      pos,
      6.5,
      Paint()
        ..color = renk.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(pos, 1.8, Paint()..color = Colors.white);
  }

  void _cizOrganikKahramanAgac(Canvas canvas, Offset kok, double birikim, int adim, bool susuz) {
    final double buyume = (birikim / 10000.0).clamp(0.18, 1.0);
    final double govdeYukseklik = 42.0 + buyume * 68.0;
    final double govdeKalinlik = 4.0 + buyume * 14.0;

    final govdePath = Path()
      ..moveTo(kok.dx - govdeKalinlik * 0.65, kok.dy)
      ..quadraticBezierTo(
        kok.dx - govdeKalinlik * 0.9,
        kok.dy - govdeYukseklik * 0.5,
        kok.dx - govdeKalinlik * 0.25,
        kok.dy - govdeYukseklik,
      )
      ..lineTo(kok.dx + govdeKalinlik * 0.25, kok.dy - govdeYukseklik)
      ..quadraticBezierTo(
        kok.dx + govdeKalinlik * 0.85,
        kok.dy - govdeYukseklik * 0.45,
        kok.dx + govdeKalinlik * 0.65,
        kok.dy,
      )
      ..close();

    canvas.drawPath(
      govdePath,
      Paint()
        ..shader = LinearGradient(
          colors: birikim < 300
              ? [const Color(0xFF059669), const Color(0xFF34D399)]
              : [const Color(0xFF451A03), const Color(0xFF92400E), const Color(0xFF78350F)],
        ).createShader(Rect.fromLTWH(kok.dx - 20, kok.dy - govdeYukseklik, 40, govdeYukseklik)),
    );

    final int dalSayisi = math.min((adim ~/ 3), 6);
    final dalPaint = Paint()
      ..color = birikim < 300 ? const Color(0xFF10B981) : const Color(0xFF78350F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (govdeKalinlik * 0.42).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final List<Offset> tacMerkezleri = [
      Offset(kok.dx, kok.dy - govdeYukseklik),
    ];

    for (int d = 0; d < dalSayisi; d++) {
      final yon = d % 2 == 0 ? -1.0 : 1.0;
      final baslangicY = kok.dy - govdeYukseklik * (0.48 + (d * 0.08));
      final uc = Offset(
        kok.dx + yon * (24.0 + buyume * 36.0 - d * 2),
        baslangicY - (14.0 + buyume * 18.0) * (susuz ? 0.6 : 1.0),
      );

      canvas.drawPath(
        Path()
          ..moveTo(kok.dx, baslangicY)
          ..quadraticBezierTo(kok.dx + yon * 14, baslangicY - 4, uc.dx, uc.dy),
        dalPaint,
      );
      tacMerkezleri.add(uc);
    }

    final koyuYaprak = susuz ? const Color(0xFF92400E) : const Color(0xFF065F46);
    final ortaYaprak = susuz ? const Color(0xFFD97706) : const Color(0xFF059669);
    final parlakYaprak = susuz ? const Color(0xFFFBBF24) : const Color(0xFF34D399);

    for (int m = 0; m < tacMerkezleri.length; m++) {
      final c = tacMerkezleri[m];
      final r = (16.0 + buyume * 26.0) * (m == 0 ? 1.25 : 0.85);

      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx, c.dy + 4), width: r * 2.1, height: r * 1.15),
        Paint()..color = koyuYaprak,
      );
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 1.9, height: r * 1.05),
        Paint()..color = ortaYaprak,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx, c.dy - 4), width: r * 1.45, height: r * 0.78),
        Paint()..color = parlakYaprak,
      );
    }

    final int meyveSayisi = math.min(adim ~/ 2, 18);
    final meyveRng = math.Random(2026);
    for (int f = 0; f < meyveSayisi; f++) {
      final merkez = tacMerkezleri[f % tacMerkezleri.length];
      final fx = merkez.dx + (meyveRng.nextDouble() - 0.5) * (24 + buyume * 30);
      final fy = merkez.dy + (meyveRng.nextDouble() - 0.5) * (12 + buyume * 14);

      canvas.drawCircle(
        Offset(fx, fy),
        6,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(Offset(fx, fy), 2.8, Paint()..color = const Color(0xFFFDE047));
    }
  }

  void _cizCurumusAgac(Canvas canvas, Offset kok) {
    final kuruPaint = Paint()
      ..color = const Color(0xFF6B7280)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      Path()
        ..moveTo(kok.dx, kok.dy)
        ..quadraticBezierTo(kok.dx - 8, kok.dy - 35, kok.dx + 12, kok.dy - 68),
      kuruPaint,
    );
    canvas.drawLine(Offset(kok.dx - 4, kok.dy - 34), Offset(kok.dx - 26, kok.dy - 54), kuruPaint..strokeWidth = 3);
    canvas.drawLine(Offset(kok.dx + 4, kok.dy - 48), Offset(kok.dx + 28, kok.dy - 42), kuruPaint);
  }

  @override
  bool shouldRepaint(covariant GercekciBotanikBahceRessami oldDelegate) {
    return oldDelegate.birikim != birikim ||
        oldDelegate.curudu != curudu ||
        oldDelegate.susuz != susuz ||
        oldDelegate.suOrani != suOrani;
  }
}