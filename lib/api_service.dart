import 'dart:convert';
import 'package:http/http.dart' as http;

import 'globals.dart';

class ApiService {
  final String url = 'https://api.textrazor.com/';

  Future<String> summarizeText(String text) async {
    final headers = {
      'x-textrazor-key': apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    final body = {
      'text': text,
      'extractors': 'entities',
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      // 응답이 UTF-8로 인코딩되어 있는지 확인
      final decodedBody = utf8.decode(response.bodyBytes);

      print('Decoded API Response: $decodedBody');
      print('Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(decodedBody) as Map<String, dynamic>;

        print('Full Response Data: ${jsonEncode(data)}');

        if (data.containsKey('response') && data['response'] != null) {
          final responseData = data['response'] as Map<String, dynamic>;

          if (responseData.containsKey('entities') &&
              responseData['entities'] != null) {
            final entities = responseData['entities'] as List<dynamic>;

            if (entities.isNotEmpty) {
              final summaries = entities.map((e) {
                final entityName =
                    e['entityId'] ?? e['entityEnglishId'] ?? 'Unknown Entity';
                final matchedText = e['matchedText'] ?? 'No matched text';
                final confidence =
                    e['confidenceScore']?.toStringAsFixed(2) ?? 'N/A';

                return '엔티티: $entityName\nMatched Text: "$matchedText"\n신뢰도: $confidence\n';
              }).join('\n');

              final summary = '텍스트에서 추출된 주요 엔티티:\n\n$summaries';
              return summary;
            } else {
              return '텍스트에서 유의미한 엔티티를 찾을 수 없습니다.';
            }
          } else {
            return '응답에서 엔티티 정보를 찾을 수 없습니다.';
          }
        } else {
          return '잘못된 응답 형식';
        }
      } else {
        throw Exception('API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('API 호출 중 오류 발생: $e');
      throw Exception('텍스트 요약 실패');
    }
  }
}

class MemoSummarizer {
  final ApiService _apiService;

  MemoSummarizer(this._apiService);

  Future<String> getSummary(String text) async {
    try {
      return await _apiService.summarizeText(text);
    } catch (e) {
      print('오류 발생: $e');
      return '텍스트 요약 실패';
    }
  }
}
