import 'package:flutter/material.dart';

class ControlsPanel extends StatelessWidget {
  final bool hasClothes;
  final bool isRaining;
  final double temperature;
  final double humidity;
  final String position;
  final String mode;
  final int stepperCommand;
  final VoidCallback onToggleHasClothes;
  final Future<void> Function(int step) onConfirmStepper;

  const ControlsPanel({
    super.key,
    required this.hasClothes,
    required this.isRaining,
    required this.temperature,
    required this.humidity,
    required this.position,
    required this.mode,
    this.stepperCommand = 0,
    required this.onToggleHasClothes,
    required this.onConfirmStepper,
  });

  Widget _sensorTile(IconData icon, String title, String value, Color color) {
    return SizedBox(
      width: 160,
      child: Row(
        children: [
          CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(child: Text('Điều khiển & Cảm biến', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Flexible(flex: 0, child: Text(mode, style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final firstCard = Card(
              color: Colors.blueGrey[25],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [Icon(Icons.checkroom, size: 28), SizedBox(width: 8), Flexible(child: Text('Quần áo trên giá', style: TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                  const SizedBox(height: 8),
                  Text('Ghi nhận liệu còn quần áo trên giá hay không. Ảnh hưởng đến hành vi tự động.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [Icon(hasClothes ? Icons.check_circle : Icons.check_circle_outline, color: hasClothes ? Colors.green : Colors.grey), const SizedBox(width: 8), Text(hasClothes ? 'Có quần áo' : 'Không có quần áo', style: const TextStyle(fontWeight: FontWeight.w600))]),
                    Semantics(container: true, label: 'Quần áo trên giá', value: hasClothes ? 'Có' : 'Không', toggled: hasClothes, child: Tooltip(message: 'Chuyển đổi trạng thái quần áo trên giá', child: Switch.adaptive(value: hasClothes, onChanged: (_) => onToggleHasClothes()))),
                  ]),
                ]),
              ),
            );

            final secondCard = Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [Icon(Icons.tune, size: 28), SizedBox(width: 8), Text('Điều khiển Stepper', style: TextStyle(fontWeight: FontWeight.w600))]),
                  const SizedBox(height: 8),
                  Text('Sử dụng để kéo ra / thu vào ngay lập tức.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        enabled: !isRaining && hasClothes && stepperCommand == 0,
                        label: 'Kéo ra',
                        child: ElevatedButton.icon(
                          onPressed: (isRaining || !hasClothes || stepperCommand != 0) ? null : () => onConfirmStepper(1),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('KÉO RA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Thu về',
                        child: ElevatedButton.icon(
                          onPressed: (stepperCommand != 0) ? null : () => onConfirmStepper(-1),
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text('THU VỀ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (isRaining) const Padding(padding: EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.warning, color: Colors.red), SizedBox(width: 8), Expanded(child: Text('Cảnh báo: Trời đang mưa — thao tác kéo ra bị khoá', style: TextStyle(color: Colors.red), maxLines: 2, overflow: TextOverflow.ellipsis))])),
                  if (stepperCommand != 0) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.sync, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text('Giàn phơi đang được ${stepperCommand == 1 ? 'kéo ra' : 'thu về'}...', style: const TextStyle(color: Colors.blue), maxLines: 2, overflow: TextOverflow.ellipsis))])),
                ]),
              ),
            );

            if (narrow) {
              return Column(children: [firstCard, const SizedBox(height: 12), secondCard]);
            }

            return Row(children: [Expanded(flex: 2, child: firstCard), const SizedBox(width: 12), Expanded(flex: 3, child: secondCard)]);
          }),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sensorTile(Icons.umbrella, 'Thời tiết', isRaining ? 'Mưa' : 'Tạnh', isRaining ? Colors.red : Colors.green),
            _sensorTile(Icons.thermostat, 'Nhiệt độ', '${temperature.toStringAsFixed(1)} °C', Colors.redAccent),
            _sensorTile(Icons.water_drop, 'Độ ẩm', '${humidity.toStringAsFixed(0)} %', Colors.blueAccent),
            _sensorTile(Icons.location_on, 'Vị trí', position, Colors.indigo),
          ]),
        ]),
      ),
    );
  }

  // Formatting helpers kept minimal (data passed in)
  
}
