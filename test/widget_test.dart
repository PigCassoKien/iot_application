import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clothesline_app/main.dart'; // Đúng tên package của bạn
import 'package:lottie/lottie.dart';

void main() {
  testWidgets('App Giàn Phơi Thông Minh - Full UI & Interaction Test', (WidgetTester tester) async {
    // Khởi động đúng tên class trong main.dart của bạn
    await tester.pumpWidget(const SmartClotheslineApp());

    // Đợi load Lottie animation + Firebase (nếu có mạng)
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 1. Kiểm tra tiêu đề AppBar
    expect(find.text('Giàn Phơi Thông Minh'), findsOneWidget);

    // 2. Kiểm tra animation Lottie hiện
    expect(find.byType(LottieBuilder), findsOneWidget);

    // 3. Kiểm tra trạng thái ban đầu
    expect(find.textContaining('ĐÃ KÉO VÀO TRONG NHÀ'), findsOneWidget);
    expect(find.text('TỰ ĐỘNG'), findsOneWidget);
    expect(find.textContaining('lx'), findsOneWidget); // ánh sáng

    // 4. Kiểm tra nút chuyển chế độ
    expect(find.text('TỰ ĐỘNG'), findsOneWidget);
    expect(find.text('THỦ CÔNG'), findsOneWidget);

    // 5. Kiểm tra thông báo chế độ tự động
    expect(find.textContaining('Chế độ TỰ ĐỘNG đang hoạt động'), findsOneWidget);

    // 6. Chuyển sang chế độ THỦ CÔNG
    await tester.tap(find.text('THỦ CÔNG'));
    await tester.pumpAndSettle();

    expect(find.text('KÉO RA PHƠI'), findsOneWidget);
    expect(find.text('KÉO VÀO NHÀ'), findsOneWidget);

    // 7. Nhấn nút "KÉO RA PHƠI" → kiểm tra trạng thái thay đổi
    await tester.tap(find.text('KÉO RA PHƠI'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('ĐANG PHƠI NGOÀI TRỜI'), findsOneWidget);

    // 8. Quay lại chế độ TỰ ĐỘNG
    await tester.tap(find.text('TỰ ĐỘNG'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chế độ TỰ ĐỘNG đang hoạt động'), findsOneWidget);

    // In ra chúc mừng
    print('TẤT CẢ TEST ĐÃ PASS! APP GIÀN PHƠI THÔNG MINH CỦA BẠN HOẠT ĐỘNG HOÀN HẢO!');
  });
}

//"C:\Users\ADMIN\AppData\Local\Android\Sdk\platform-tools\adb.exe" logcat *:E flutter:D Unity:I | findstr /R "com\.example\.application FLT"