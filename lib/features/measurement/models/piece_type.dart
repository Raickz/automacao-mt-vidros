enum PieceType {
  box2Folhas,
  box3Folhas,
  guardaCorpo,
  porta,
  janela,
  fachada,
  livre,
}

extension PieceTypeX on PieceType {
  String get label {
    switch (this) {
      case PieceType.box2Folhas:
        return 'Box 2 folhas';
      case PieceType.box3Folhas:
        return 'Box 3 folhas';
      case PieceType.guardaCorpo:
        return 'Guarda-corpo';
      case PieceType.porta:
        return 'Porta';
      case PieceType.janela:
        return 'Janela';
      case PieceType.fachada:
        return 'Fachada';
      case PieceType.livre:
        return 'Formato livre';
    }
  }

  bool get isRectangular => this != PieceType.livre;

  int get requiredPoints => isRectangular ? 4 : -1;
}
