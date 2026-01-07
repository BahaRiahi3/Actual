import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'login_page.dart';
import 'saved_page.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE94057)),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
             return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return const NewsSwipeScreen();
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }
}

class NewsSwipeScreen extends StatefulWidget {
  const NewsSwipeScreen({super.key});

  @override
  State<NewsSwipeScreen> createState() => _NewsSwipeScreenState();
}

class _NewsSwipeScreenState extends State<NewsSwipeScreen> {
  final CardSwiperController controller = CardSwiperController();
  bool _allCaughtUp = false; 

  Future<List<QueryDocumentSnapshot>> _fetchNews() async {
    var snapshot = await FirebaseFirestore.instance.collection('news_segments').get();
    return snapshot.docs;
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch $uri');
    }
  }

  void _resetCards() {
    setState(() {
      _allCaughtUp = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text("Swipy News", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.bookmarks_outlined, color: Colors.black),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SavedPage()));
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: _allCaughtUp 
        ? _buildWaitScreen() 
        : _buildCardStack(), 
    );
  }

  // 1. The Normal Card Stack
  Widget _buildCardStack() {
    return FutureBuilder<List<QueryDocumentSnapshot>>(
      future: _fetchNews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No news available yet."));
        }

        final cards = snapshot.data!;

        return SafeArea(
          child: Column(
            children: [
              Flexible(
                child: CardSwiper(
                  controller: controller,
                  cardsCount: cards.length,
                  numberOfCardsDisplayed: 3,
                  backCardOffset: const Offset(0, 40),
                  padding: const EdgeInsets.all(24.0),
                  onSwipe: (previousIndex, currentIndex, direction) {
                    
                    // Left to Read logic
                    if (direction == CardSwiperDirection.left) {
                      var data = cards[previousIndex].data() as Map<String, dynamic>;
                      _launchURL(data['articleUrl']);
                    }
                    return true;
                  },
                  onEnd: () {
                    setState(() {
                      _allCaughtUp = true;
                    });
                  },
                  cardBuilder: (context, index, percentThresholdX, percentThresholdY) {
                    var data = cards[index].data() as Map<String, dynamic>;
                    // Includes the Key fix
                    return NewsCard(
                      key: ValueKey(data['articleUrl']), 
                      data: data
                    );
                  },
                ),
              ),
              
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  "← Read      •      Skip →", 
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // 2. The "Wait" Screen
  Widget _buildWaitScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.network(
              'https://raw.githubusercontent.com/xvrh/lottie-flutter/master/example/assets/lottiefiles/empty_box.json',
              height: 250,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.check_circle_outline, size: 100, color: Colors.green);
              },
            ),
            const SizedBox(height: 30),
            const Text("You're all caught up!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text("New stories arrive in ~5 hours.", style: TextStyle(fontSize: 16, color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            OutlinedButton(onPressed: _resetCards, child: const Text("Re-read Old Stories"))
          ],
        ),
      ),
    );
  }
}

// --- UPDATED SMART NEWS CARD ---
class NewsCard extends StatefulWidget {
  final Map<String, dynamic> data;

  const NewsCard({super.key, required this.data});

  @override
  State<NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<NewsCard> {
  bool isSaved = false;
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _checkStatus(); // 1. Check database when card loads
  }

  // Check if article is already in Firestore
  Future<void> _checkStatus() async {
    if (user == null) return;
    
    // Query saved items where the URL matches this card
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('saved')
        .where('articleUrl', isEqualTo: widget.data['articleUrl'])
        .get();

    if (mounted && query.docs.isNotEmpty) {
      setState(() {
        isSaved = true; // Turn icon red if found
      });
    }
  }

  // Add or Remove (Toggle)
  Future<void> _toggleSave() async {
    if (user == null) return;

    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('saved');

    // Optimistic UI update (makes app feel fast)
    setState(() {
      isSaved = !isSaved;
    });

    if (isSaved) {
      // --- SAVE (Prevent Duplicates) ---
      final existing = await collection
          .where('articleUrl', isEqualTo: widget.data['articleUrl'])
          .get();

      if (existing.docs.isEmpty) {
        await collection.add({
          ...widget.data,
          'savedAt': FieldValue.serverTimestamp(),
        });
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved to library!"), duration: Duration(milliseconds: 500)));
      }
    } else {
      // --- UNSAVE (Remove from DB) ---
      final query = await collection
          .where('articleUrl', isEqualTo: widget.data['articleUrl'])
          .get();

      for (var doc in query.docs) {
        await doc.reference.delete();
      }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Removed from library."), duration: Duration(milliseconds: 500)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 10))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: widget.data['imageUrl'] ?? '',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.grey[200]),
                errorWidget: (context, url, error) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.0),
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.9),
                    ],
                    stops: const [0.0, 0.5, 0.75, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFFE94057), borderRadius: BorderRadius.circular(8)),
                    child: Text(widget.data['source']?.toUpperCase() ?? "NEWS", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.data['title'] ?? "No Title", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(widget.data['summary'] ?? "No summary.", style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9), height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          final url = widget.data['articleUrl'] ?? '';
                          if (url.isNotEmpty) Share.share("Check out this story: $url");
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                      ),
                      
                      const Text("← Swipe Left to Read", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      
                      IconButton(
                        onPressed: _toggleSave,
                        icon: Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border, 
                          color: isSaved ? const Color(0xFFE94057) : Colors.white
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}