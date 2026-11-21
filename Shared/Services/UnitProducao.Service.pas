unit UnitProducao.Service;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.JSON,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TProducaoService = class
  private
    class var FEstruturaVerificada: Boolean;
    class var FLockEstrutura: TObject;
    class constructor Create;
    class destructor Destroy;
    class procedure ExecutarDDL(Conn: TFDConnection; Trans: TFDTransaction; const SQL: string); static;
    class function GerarCodigoTabela(Conn: TFDConnection; Trans: TFDTransaction; const Tabela, Campo: string): Integer; static;
    class function GerarProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer; static;
    class function DFSBuscaAlvo(Conn: TFDConnection; Trans: TFDTransaction; CodAlvoProcurado, CodAtual: Integer; Visitados: TDictionary<Integer, Boolean>): Boolean; static;
  public
    class procedure GarantirEstrutura; static;
    class function TabelaExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeTabela: string): Boolean; static;
    class function ColunaExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeTabela, NomeColuna: string): Boolean; static;
    class function GeneratorExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Boolean; static;
    class function NormalizarTipoProduto(const ATipo: string): string; static;
    class function NormalizarUnidade(const AUnidade: string): string; static;
    class function CalcularFatorConversao(const AUnidadeReceita, AUnidadeBase: string): Double; static;
    class function VerificarCiclo(Conn: TFDConnection; Trans: TFDTransaction; CodProdutoAlvo: Integer; const Insumos: TArray<Integer>): Boolean; static;
    class procedure RecalcularFicha(Conn: TFDConnection; Trans: TFDTransaction; CodFT: Integer; out CustoAnterior, CustoNovo: Double; out TipoAlvo: string; out CodAlvo: Integer; out NomeAlvo: string); static;
    class procedure RecalcularEmCascata(Conn: TFDConnection; Trans: TFDTransaction; CodProdutoInsumo: Integer; Recalculadas: TJSONArray; Visitados: TDictionary<Integer, Boolean> = nil); static;
    class procedure AtualizarCustoEstoqueCompra(Conn: TFDConnection; Trans: TFDTransaction; CodPro: Integer; QtdEntrada, CustoUnitEntrada: Double; const Origem, Doc: string; DataNota: TDate; out NovoCM, NovoEstoque: Double); static;
    class function BaixarInsumosECalcularCusto(Conn: TFDConnection; Trans: TFDTransaction; const TipoAlvo: string; CodAlvo: Integer; QtdVendida: Double; CodVenda: Integer; out UsouFicha: Boolean; Depth: Integer = 0; Visitados: TDictionary<string, Boolean> = nil): Double; static;
  end;

implementation

uses
  Data.DB,
  UnitConnection.Model.Interfaces,
  UnitDatabase;

{ TProducaoService }

class constructor TProducaoService.Create;
begin
  FLockEstrutura := TObject.Create;
  FEstruturaVerificada := False;
end;

class destructor TProducaoService.Destroy;
begin
  FLockEstrutura.Free;
end;

class function TProducaoService.TabelaExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeTabela: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT COUNT(*) AS QTD FROM RDB$RELATIONS WHERE UPPER(TRIM(RDB$RELATION_NAME)) = :NOME';
    Q.ParamByName('NOME').AsString := UpperCase(Trim(NomeTabela));
    Q.Open;
    Result := Q.FieldByName('QTD').AsInteger > 0;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.ColunaExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeTabela, NomeColuna: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text :=
      'SELECT COUNT(*) AS QTD FROM RDB$RELATION_FIELDS ' +
      'WHERE UPPER(TRIM(RDB$RELATION_NAME)) = :TABELA ' +
      '  AND UPPER(TRIM(RDB$FIELD_NAME)) = :COLUNA';
    Q.ParamByName('TABELA').AsString := UpperCase(Trim(NomeTabela));
    Q.ParamByName('COLUNA').AsString := UpperCase(Trim(NomeColuna));
    Q.Open;
    Result := Q.FieldByName('QTD').AsInteger > 0;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.GeneratorExiste(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT COUNT(*) AS QTD FROM RDB$GENERATORS WHERE UPPER(TRIM(RDB$GENERATOR_NAME)) = :NOME';
    Q.ParamByName('NOME').AsString := UpperCase(Trim(NomeGen));
    Q.Open;
    Result := Q.FieldByName('QTD').AsInteger > 0;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TProducaoService.ExecutarDDL(Conn: TFDConnection; Trans: TFDTransaction; const SQL: string);
var
  Q: TFDQuery;
begin
  if not Trans.Active then
    Trans.StartTransaction;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := SQL;
    Q.ExecSQL;
    Trans.Commit;
  except
    if Trans.Active then
      Trans.Rollback;
    raise;
  end;
  Q.DisposeOf;
end;

class procedure TProducaoService.GarantirEstrutura;
var
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;

  procedure GarantirGen(const NomeGen: string);
  begin
    if not Transacao.Active then
      Transacao.StartTransaction;
    if not GeneratorExiste(Conexao, Transacao, NomeGen) then
    begin
      Transacao.Commit;
      ExecutarDDL(Conexao, Transacao, 'CREATE GENERATOR ' + NomeGen);
    end
    else
      Transacao.Commit;
  end;

begin
  if FEstruturaVerificada then
    Exit;

  TMonitor.Enter(FLockEstrutura);
  try
    if FEstruturaVerificada then
      Exit;

    BancoDados := TDatabase.Connection;
    IndiceConexao := BancoDados.Connected;
    Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
    Transacao := TFDTransaction.Create(nil);
    try
      Transacao.Connection := Conexao;
      Transacao.Options.Params.Clear;
      Transacao.Options.Params.Add('write');
      Transacao.Options.Params.Add('read_committed');
      Transacao.Options.Params.Add('rec_version');
      Transacao.Options.Params.Add('nowait');

      // 1. Coluna VO_OP em VE_OPCOES
      Transacao.StartTransaction;
      if TabelaExiste(Conexao, Transacao, 'VE_OPCOES') and
         (not ColunaExiste(Conexao, Transacao, 'VE_OPCOES', 'VO_OP')) then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao, 'ALTER TABLE VE_OPCOES ADD VO_OP INTEGER');
      end
      else if Transacao.Active then
        Transacao.Commit;

      // 2. PROD_FORN_MAP
      Transacao.StartTransaction;
      if not TabelaExiste(Conexao, Transacao, 'PROD_FORN_MAP') then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao,
          'CREATE TABLE PROD_FORN_MAP (' +
          '  PFM_CODIGO INTEGER NOT NULL PRIMARY KEY,' +
          '  PFM_CNPJ_FORN VARCHAR(20),' +
          '  PFM_COD_FORN_ITEM VARCHAR(60),' +
          '  PFM_EAN VARCHAR(20),' +
          '  PFM_NOME_NF VARCHAR(150),' +
          '  PFM_PRO INTEGER,' +
          '  PFM_DESTINO VARCHAR(15),' +
          '  PFM_FATOR_CONV NUMERIC(12,4),' +
          '  PFM_UNIDADE_NF VARCHAR(10),' +
          '  PFM_SUD INTEGER,' +
          '  PFM_DATAU TIMESTAMP' +
          ')');
      end
      else if Transacao.Active then
        Transacao.Commit;
      GarantirGen('GEN_PFM');

      // 3. NFCE_IMPORTACOES
      Transacao.StartTransaction;
      if not TabelaExiste(Conexao, Transacao, 'NFCE_IMPORTACOES') then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao,
          'CREATE TABLE NFCE_IMPORTACOES (' +
          '  NI_CODIGO INTEGER NOT NULL PRIMARY KEY,' +
          '  NI_CHAVE VARCHAR(44),' +
          '  NI_URL VARCHAR(500),' +
          '  NI_NUMERO VARCHAR(20),' +
          '  NI_SERIE VARCHAR(10),' +
          '  NI_DATA_EMISSAO DATE,' +
          '  NI_DATA_IMPORT TIMESTAMP,' +
          '  NI_CNPJ_EMIT VARCHAR(20),' +
          '  NI_NOME_EMIT VARCHAR(120),' +
          '  NI_FOR INTEGER,' +
          '  NI_MODO VARCHAR(15),' +
          '  NI_VALOR_TOTAL NUMERIC(12,2),' +
          '  NI_VALOR_DESCONTO NUMERIC(12,2),' +
          '  NI_COM_CODIGO INTEGER,' +
          '  NI_CUST_CODIGO INTEGER,' +
          '  NI_FAT2_CODIGO INTEGER,' +
          '  NI_CONTA INTEGER,' +
          '  NI_FORMA_PGTO VARCHAR(20),' +
          '  NI_FUN INTEGER' +
          ')');
      end
      else if Transacao.Active then
        Transacao.Commit;
      GarantirGen('GEN_NFCE_IMP');

      // 4. NFCE_IMPORTACAO_ITENS
      Transacao.StartTransaction;
      if not TabelaExiste(Conexao, Transacao, 'NFCE_IMPORTACAO_ITENS') then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao,
          'CREATE TABLE NFCE_IMPORTACAO_ITENS (' +
          '  NII_CODIGO INTEGER NOT NULL PRIMARY KEY,' +
          '  NII_NI INTEGER NOT NULL,' +
          '  NII_COD_FORN VARCHAR(60),' +
          '  NII_EAN VARCHAR(20),' +
          '  NII_DESCRICAO VARCHAR(150),' +
          '  NII_QTD_NF NUMERIC(12,4),' +
          '  NII_UNIDADE_NF VARCHAR(10),' +
          '  NII_VLR_UNIT_NF NUMERIC(12,4),' +
          '  NII_VLR_TOTAL NUMERIC(12,2),' +
          '  NII_DESTINO VARCHAR(15),' +
          '  NII_PRO INTEGER,' +
          '  NII_FATOR_CONV NUMERIC(12,4),' +
          '  NII_QTD_ESTOQUE NUMERIC(12,4),' +
          '  NII_CUSTO_UNIT_ESTOQUE NUMERIC(12,4)' +
          ')');
      end
      else if Transacao.Active then
        Transacao.Commit;
      GarantirGen('GEN_NFCE_IMP_IT');

      // 5. FICHA_TECNICA
      Transacao.StartTransaction;
      if not TabelaExiste(Conexao, Transacao, 'FICHA_TECNICA') then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao,
          'CREATE TABLE FICHA_TECNICA (' +
          '  FT_CODIGO INTEGER NOT NULL PRIMARY KEY,' +
          '  FT_TIPO_ALVO VARCHAR(15) NOT NULL,' +
          '  FT_COD_ALVO INTEGER NOT NULL,' +
          '  FT_NOME VARCHAR(120),' +
          '  FT_RENDIMENTO NUMERIC(12,4),' +
          '  FT_UNIDADE_REND VARCHAR(10),' +
          '  FT_PERDA_PERC NUMERIC(9,2),' +
          '  FT_MARKUP_PERC NUMERIC(9,2),' +
          '  FT_CUSTO_INDIRETO NUMERIC(12,4),' +
          '  FT_MODO_PREPARO VARCHAR(2000),' +
          '  FT_CUSTO_TOTAL NUMERIC(12,4),' +
          '  FT_CUSTO_UNIT NUMERIC(12,4),' +
          '  FT_ATIVO CHAR(1),' +
          '  FT_DATA_ATUALIZACAO TIMESTAMP' +
          ')');
      end
      else if Transacao.Active then
        Transacao.Commit;
      GarantirGen('GEN_FT');

      // 6. FICHA_TECNICA_ITENS
      Transacao.StartTransaction;
      if not TabelaExiste(Conexao, Transacao, 'FICHA_TECNICA_ITENS') then
      begin
        Transacao.Commit;
        ExecutarDDL(Conexao, Transacao,
          'CREATE TABLE FICHA_TECNICA_ITENS (' +
          '  FTI_CODIGO INTEGER NOT NULL PRIMARY KEY,' +
          '  FTI_FT INTEGER NOT NULL,' +
          '  FTI_PRO_INSUMO INTEGER NOT NULL,' +
          '  FTI_QUANTIDADE NUMERIC(12,4) NOT NULL,' +
          '  FTI_UNIDADE VARCHAR(10) NOT NULL,' +
          '  FTI_FATOR_BASE NUMERIC(12,6),' +
          '  FTI_CUSTO_UNIT_SNAP NUMERIC(12,4),' +
          '  FTI_CUSTO_TOTAL NUMERIC(12,4),' +
          '  FTI_PERCENTUAL NUMERIC(9,2)' +
          ')');
      end
      else if Transacao.Active then
        Transacao.Commit;
      GarantirGen('GEN_FTI');

      // Generators padrao que serao usados nas importacoes/compras
      GarantirGen('GEN_COM');
      GarantirGen('GEN_CE');
      GarantirGen('GEN_FAT2');
      GarantirGen('GEN_CUST');
      GarantirGen('GEN_PAG');
      GarantirGen('GEN_MOV');
      GarantirGen('GEN_PP');
      GarantirGen('GEN_HP');

      FEstruturaVerificada := True;
    finally
      if Transacao.Active then
        Transacao.Rollback;
      Transacao.DisposeOf;
      BancoDados.Disconnected(IndiceConexao);
    end;
  finally
    TMonitor.Exit(FLockEstrutura);
  end;
end;

class function TProducaoService.GerarCodigoTabela(Conn: TFDConnection; Trans: TFDTransaction; const Tabela, Campo: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT COALESCE(MAX(' + Campo + '), 0) + 1 AS PROX FROM ' + Tabela;
    Q.Open;
    Result := Q.FieldByName('PROX').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.GerarProximoGen(Conn: TFDConnection; Trans: TFDTransaction; const NomeGen: string): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text := 'SELECT GEN_ID(' + UpperCase(Trim(NomeGen)) + ', 1) AS ID FROM RDB$DATABASE';
    Q.Open;
    Result := Q.FieldByName('ID').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.NormalizarTipoProduto(const ATipo: string): string;
var
  T: string;
begin
  T := UpperCase(Trim(ATipo));
  if (T = 'MP') or (T = 'MATERIA_PRIMA') or (T = 'MATERIA-PRIMA') or (T = 'MATERIA PRIMA') then
    Result := 'MP'
  else if (T = 'PRODUCAO') or (T = 'PRODUÇÃO') or (T = 'PROD') then
    Result := 'PRODUCAO'
  else
    Result := 'REVENDA';
end;

class function TProducaoService.NormalizarUnidade(const AUnidade: string): string;
var
  U: string;
begin
  U := UpperCase(Trim(AUnidade));
  if (U = 'KG') or (U = 'KGS') or (U = 'QUILO') or (U = 'QUILOS') or (U = 'KILO') then
    Result := 'KG'
  else if (U = 'G') or (U = 'GR') or (U = 'GRS') or (U = 'GRAMA') or (U = 'GRAMAS') then
    Result := 'G'
  else if (U = 'MG') then
    Result := 'MG'
  else if (U = 'L') or (U = 'LT') or (U = 'LTS') or (U = 'LITRO') or (U = 'LITROS') then
    Result := 'L'
  else if (U = 'ML') or (U = 'MLS') or (U = 'MILILITRO') or (U = 'MILILITROS') then
    Result := 'ML'
  else if (U = 'UN') or (U = 'UND') or (U = 'UNID') or (U = 'UNIDADE') or (U = 'PC') or (U = 'PÇ') or (U = 'PCT') then
  begin
    if U = 'PCT' then
      Result := 'PCT'
    else
      Result := 'UN';
  end
  else if U = '' then
    Result := 'UN'
  else
    Result := Copy(U, 1, 10);
end;

class function TProducaoService.CalcularFatorConversao(const AUnidadeReceita, AUnidadeBase: string): Double;
var
  UR, UB: string;
begin
  UR := NormalizarUnidade(AUnidadeReceita);
  UB := NormalizarUnidade(AUnidadeBase);

  if UR = UB then
    Exit(1.0);

  // Massa
  if (UR = 'G') and (UB = 'KG') then Exit(0.001);
  if (UR = 'KG') and (UB = 'G') then Exit(1000.0);
  if (UR = 'MG') and (UB = 'G') then Exit(0.001);
  if (UR = 'G') and (UB = 'MG') then Exit(1000.0);
  if (UR = 'MG') and (UB = 'KG') then Exit(0.000001);
  if (UR = 'KG') and (UB = 'MG') then Exit(1000000.0);

  // Volume
  if (UR = 'ML') and (UB = 'L') then Exit(0.001);
  if (UR = 'L') and (UB = 'ML') then Exit(1000.0);

  Result := 1.0;
end;

class function TProducaoService.DFSBuscaAlvo(Conn: TFDConnection; Trans: TFDTransaction; CodAlvoProcurado, CodAtual: Integer; Visitados: TDictionary<Integer, Boolean>): Boolean;
var
  Q: TFDQuery;
  Prox: Integer;
begin
  Result := False;
  if CodAtual <= 0 then
    Exit;
  if CodAtual = CodAlvoProcurado then
    Exit(True);
  if Visitados.ContainsKey(CodAtual) then
    Exit;

  Visitados.Add(CodAtual, True);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text :=
      'SELECT I.FTI_PRO_INSUMO ' +
      'FROM FICHA_TECNICA F ' +
      'JOIN FICHA_TECNICA_ITENS I ON I.FTI_FT = F.FT_CODIGO ' +
      'WHERE F.FT_TIPO_ALVO = ''PRODUTO'' AND F.FT_COD_ALVO = :COD AND COALESCE(F.FT_ATIVO, ''S'') = ''S''';
    Q.ParamByName('COD').AsInteger := CodAtual;
    Q.Open;
    while not Q.Eof do
    begin
      Prox := Q.FieldByName('FTI_PRO_INSUMO').AsInteger;
      if DFSBuscaAlvo(Conn, Trans, CodAlvoProcurado, Prox, Visitados) then
        Exit(True);
      Q.Next;
    end;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.VerificarCiclo(Conn: TFDConnection; Trans: TFDTransaction; CodProdutoAlvo: Integer; const Insumos: TArray<Integer>): Boolean;
var
  Visitados: TDictionary<Integer, Boolean>;
  Insumo: Integer;
begin
  Result := False;
  if CodProdutoAlvo <= 0 then
    Exit;
  Visitados := TDictionary<Integer, Boolean>.Create;
  try
    for Insumo in Insumos do
    begin
      if Insumo = CodProdutoAlvo then
        Exit(True);
      if DFSBuscaAlvo(Conn, Trans, CodProdutoAlvo, Insumo, Visitados) then
        Exit(True);
    end;
  finally
    Visitados.Free;
  end;
end;

class procedure TProducaoService.RecalcularFicha(Conn: TFDConnection; Trans: TFDTransaction; CodFT: Integer; out CustoAnterior, CustoNovo: Double; out TipoAlvo: string; out CodAlvo: Integer; out NomeAlvo: string);
var
  Q, QUpd: TFDQuery;
  Rendimento, Perda, CustoIndireto, RendimentoEfetivo: Double;
  SomaInsumos, CustoLote: Double;
  QtdItem, FatorBase, CustoUnitInsumo, CustoTotalItem, Perc: Double;
  CodItem: Integer;
  UnidadeItem, UnidadeBasePro: string;
begin
  CustoAnterior := 0;
  CustoNovo := 0;
  TipoAlvo := '';
  CodAlvo := 0;
  NomeAlvo := '';

  Q := TFDQuery.Create(nil);
  QUpd := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    QUpd.Connection := Conn;
    QUpd.Transaction := Trans;

    Q.SQL.Text :=
      'SELECT FT_TIPO_ALVO, FT_COD_ALVO, FT_NOME, FT_RENDIMENTO, FT_PERDA_PERC, FT_CUSTO_INDIRETO, FT_CUSTO_UNIT ' +
      'FROM FICHA_TECNICA WHERE FT_CODIGO = :COD';
    Q.ParamByName('COD').AsInteger := CodFT;
    Q.Open;
    if Q.IsEmpty then
      Exit;

    TipoAlvo := UpperCase(Trim(Q.FieldByName('FT_TIPO_ALVO').AsString));
    CodAlvo := Q.FieldByName('FT_COD_ALVO').AsInteger;
    NomeAlvo := Q.FieldByName('FT_NOME').AsString;
    Rendimento := Q.FieldByName('FT_RENDIMENTO').AsFloat;
    Perda := Q.FieldByName('FT_PERDA_PERC').AsFloat;
    CustoIndireto := Q.FieldByName('FT_CUSTO_INDIRETO').AsFloat;
    CustoAnterior := Q.FieldByName('FT_CUSTO_UNIT').AsFloat;

    if Rendimento <= 0 then
      Rendimento := 1.0;
    if Perda < 0 then
      Perda := 0
    else if Perda > 95 then
      Perda := 95;

    // Passo 1: recalcula o custo de cada insumo
    SomaInsumos := 0;
    Q.Close;
    Q.SQL.Text :=
      'SELECT I.FTI_CODIGO, I.FTI_QUANTIDADE, I.FTI_UNIDADE, I.FTI_FATOR_BASE, ' +
      '       COALESCE(NULLIF(P.PRO_VALORCM, 0), P.PRO_VALORC, 0) AS CUSTO_BASE, ' +
      '       COALESCE(P.PRO_EMBALAGEM, '''') AS UNIDADE_BASE ' +
      'FROM FICHA_TECNICA_ITENS I ' +
      'JOIN PRODUTOS P ON P.PRO_CODIGO = I.FTI_PRO_INSUMO ' +
      'WHERE I.FTI_FT = :FT';
    Q.ParamByName('FT').AsInteger := CodFT;
    Q.Open;
    while not Q.Eof do
    begin
      CodItem := Q.FieldByName('FTI_CODIGO').AsInteger;
      QtdItem := Q.FieldByName('FTI_QUANTIDADE').AsFloat;
      UnidadeItem := Q.FieldByName('FTI_UNIDADE').AsString;
      FatorBase := Q.FieldByName('FTI_FATOR_BASE').AsFloat;
      UnidadeBasePro := Q.FieldByName('UNIDADE_BASE').AsString;
      if FatorBase <= 0 then
        FatorBase := CalcularFatorConversao(UnidadeItem, UnidadeBasePro);
      CustoUnitInsumo := Q.FieldByName('CUSTO_BASE').AsFloat;
      CustoTotalItem := RoundTo(QtdItem * FatorBase * CustoUnitInsumo, -4);
      SomaInsumos := SomaInsumos + CustoTotalItem;

      QUpd.Close;
      QUpd.SQL.Text :=
        'UPDATE FICHA_TECNICA_ITENS ' +
        'SET FTI_FATOR_BASE = :FATOR, FTI_CUSTO_UNIT_SNAP = :SNAP, FTI_CUSTO_TOTAL = :TOTAL ' +
        'WHERE FTI_CODIGO = :COD';
      QUpd.ParamByName('FATOR').AsFloat := FatorBase;
      QUpd.ParamByName('SNAP').AsFloat := CustoUnitInsumo;
      QUpd.ParamByName('TOTAL').AsFloat := CustoTotalItem;
      QUpd.ParamByName('COD').AsInteger := CodItem;
      QUpd.ExecSQL;

      Q.Next;
    end;

    // Passo 2: atualiza percentuais de participacao
    CustoLote := RoundTo(SomaInsumos + CustoIndireto, -4);
    RendimentoEfetivo := Max(0.0001, Rendimento * (1.0 - (Perda / 100.0)));
    CustoNovo := RoundTo(CustoLote / RendimentoEfetivo, -4);

    Q.First;
    while not Q.Eof do
    begin
      CodItem := Q.FieldByName('FTI_CODIGO').AsInteger;
      QtdItem := Q.FieldByName('FTI_QUANTIDADE').AsFloat;
      UnidadeItem := Q.FieldByName('FTI_UNIDADE').AsString;
      FatorBase := Q.FieldByName('FTI_FATOR_BASE').AsFloat;
      UnidadeBasePro := Q.FieldByName('UNIDADE_BASE').AsString;
      if FatorBase <= 0 then
        FatorBase := CalcularFatorConversao(UnidadeItem, UnidadeBasePro);
      CustoUnitInsumo := Q.FieldByName('CUSTO_BASE').AsFloat;
      CustoTotalItem := RoundTo(QtdItem * FatorBase * CustoUnitInsumo, -4);
      if SomaInsumos > 0 then
        Perc := RoundTo((CustoTotalItem / SomaInsumos) * 100.0, -2)
      else
        Perc := 0;

      QUpd.Close;
      QUpd.SQL.Text := 'UPDATE FICHA_TECNICA_ITENS SET FTI_PERCENTUAL = :PERC WHERE FTI_CODIGO = :COD';
      QUpd.ParamByName('PERC').AsFloat := Perc;
      QUpd.ParamByName('COD').AsInteger := CodItem;
      QUpd.ExecSQL;

      Q.Next;
    end;

    // Passo 3: atualiza cabecalho da ficha
    QUpd.Close;
    QUpd.SQL.Text :=
      'UPDATE FICHA_TECNICA ' +
      'SET FT_CUSTO_TOTAL = :TOTAL, FT_CUSTO_UNIT = :UNIT, FT_DATA_ATUALIZACAO = CURRENT_TIMESTAMP ' +
      'WHERE FT_CODIGO = :COD';
    QUpd.ParamByName('TOTAL').AsFloat := CustoLote;
    QUpd.ParamByName('UNIT').AsFloat := CustoNovo;
    QUpd.ParamByName('COD').AsInteger := CodFT;
    QUpd.ExecSQL;

    // Passo 4: se o alvo for PRODUTO, atualiza PRO_VALORC e PRO_VALORCM
    if TipoAlvo = 'PRODUTO' then
    begin
      QUpd.Close;
      QUpd.SQL.Text :=
        'UPDATE PRODUTOS ' +
        'SET PRO_VALORC = :CUSTO, PRO_VALORCM = :CUSTO, PRO_DATAUA = CURRENT_DATE ' +
        'WHERE PRO_CODIGO = :PRO';
      QUpd.ParamByName('CUSTO').AsFloat := CustoNovo;
      QUpd.ParamByName('PRO').AsInteger := CodAlvo;
      QUpd.ExecSQL;
    end;
  finally
    Q.DisposeOf;
    QUpd.DisposeOf;
  end;
end;

class procedure TProducaoService.RecalcularEmCascata(Conn: TFDConnection; Trans: TFDTransaction; CodProdutoInsumo: Integer; Recalculadas: TJSONArray; Visitados: TDictionary<Integer, Boolean>);
var
  CreatedDict: Boolean;
  Q: TFDQuery;
  CodFT, CodAlvo: Integer;
  CustoAnt, CustoNov: Double;
  TipoAlvo, NomeAlvo: string;
  ItemObj: TJSONObject;
  ProxPais: TList<Integer>;
begin
  if CodProdutoInsumo <= 0 then
    Exit;

  CreatedDict := Visitados = nil;
  if CreatedDict then
    Visitados := TDictionary<Integer, Boolean>.Create;
  ProxPais := TList<Integer>.Create;
  Q := TFDQuery.Create(nil);
  try
    if Visitados.ContainsKey(CodProdutoInsumo) then
      Exit;
    Visitados.Add(CodProdutoInsumo, True);

    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text :=
      'SELECT DISTINCT F.FT_CODIGO ' +
      'FROM FICHA_TECNICA F ' +
      'JOIN FICHA_TECNICA_ITENS I ON I.FTI_FT = F.FT_CODIGO ' +
      'WHERE I.FTI_PRO_INSUMO = :INSUMO AND COALESCE(F.FT_ATIVO, ''S'') = ''S''';
    Q.ParamByName('INSUMO').AsInteger := CodProdutoInsumo;
    Q.Open;
    while not Q.Eof do
    begin
      CodFT := Q.FieldByName('FT_CODIGO').AsInteger;
      RecalcularFicha(Conn, Trans, CodFT, CustoAnt, CustoNov, TipoAlvo, CodAlvo, NomeAlvo);
      if Assigned(Recalculadas) then
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.AddPair('codigo_ficha', TJSONNumber.Create(CodFT));
        ItemObj.AddPair('tipo_alvo', TipoAlvo);
        ItemObj.AddPair('cod_alvo', TJSONNumber.Create(CodAlvo));
        ItemObj.AddPair('nome', NomeAlvo);
        ItemObj.AddPair('custo_anterior', TJSONNumber.Create(RoundTo(CustoAnt, -4)));
        ItemObj.AddPair('custo_novo', TJSONNumber.Create(RoundTo(CustoNov, -4)));
        Recalculadas.AddElement(ItemObj);
      end;
      if (TipoAlvo = 'PRODUTO') and (CodAlvo > 0) and (not Visitados.ContainsKey(CodAlvo)) then
        ProxPais.Add(CodAlvo);
      Q.Next;
    end;

    for CodAlvo in ProxPais do
      RecalcularEmCascata(Conn, Trans, CodAlvo, Recalculadas, Visitados);
  finally
    Q.DisposeOf;
    ProxPais.Free;
    if CreatedDict then
      Visitados.Free;
  end;
end;

class procedure TProducaoService.AtualizarCustoEstoqueCompra(Conn: TFDConnection; Trans: TFDTransaction; CodPro: Integer; QtdEntrada, CustoUnitEntrada: Double; const Origem, Doc: string; DataNota: TDate; out NovoCM, NovoEstoque: Double);
var
  Q: TFDQuery;
  QtdAtual, QtdBase, ValorCM, ValorC, CmBase, ValorV, ValorL, ValorF: Double;
  CodHis: Integer;
begin
  NovoCM := CustoUnitEntrada;
  NovoEstoque := QtdEntrada;

  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    Q.SQL.Text :=
      'SELECT COALESCE(PRO_QUANTIDADE, 0) PRO_QUANTIDADE, ' +
      '       COALESCE(PRO_VALORCM, 0) PRO_VALORCM, ' +
      '       COALESCE(PRO_VALORC, 0) PRO_VALORC, ' +
      '       COALESCE(PRO_VALORV, 0) PRO_VALORV, ' +
      '       COALESCE(PRO_VALORL, 0) PRO_VALORL, ' +
      '       COALESCE(PRO_VALORF, 0) PRO_VALORF ' +
      'FROM PRODUTOS WHERE PRO_CODIGO = :PRO';
    Q.ParamByName('PRO').AsInteger := CodPro;
    Q.Open;
    if Q.IsEmpty then
      raise Exception.CreateFmt('Produto %d nao encontrado ao atualizar compra.', [CodPro]);

    QtdAtual := Q.FieldByName('PRO_QUANTIDADE').AsFloat;
    ValorCM := Q.FieldByName('PRO_VALORCM').AsFloat;
    ValorC := Q.FieldByName('PRO_VALORC').AsFloat;
    ValorV := Q.FieldByName('PRO_VALORV').AsFloat;
    ValorL := Q.FieldByName('PRO_VALORL').AsFloat;
    ValorF := Q.FieldByName('PRO_VALORF').AsFloat;

    QtdBase := Max(0.0, QtdAtual);
    if ValorCM > 0 then
      CmBase := ValorCM
    else
      CmBase := ValorC;

    if (QtdBase > 0) and (CmBase > 0) and (QtdEntrada > 0) then
      NovoCM := RoundTo(((QtdBase * CmBase) + (QtdEntrada * CustoUnitEntrada)) / (QtdBase + QtdEntrada), -4)
    else
      NovoCM := RoundTo(CustoUnitEntrada, -4);

    NovoEstoque := RoundTo(QtdAtual + QtdEntrada, -4);

    Q.Close;
    Q.SQL.Text :=
      'UPDATE PRODUTOS ' +
      'SET PRO_QUANTIDADE = :QTD, PRO_VALORC = :VALORC, PRO_VALORCM = :VALORCM, ' +
      '    PRO_DATAUC = :DATAUC, PRO_DATAUA = CURRENT_DATE ' +
      'WHERE PRO_CODIGO = :PRO';
    Q.ParamByName('QTD').AsFloat := NovoEstoque;
    Q.ParamByName('VALORC').AsFloat := RoundTo(CustoUnitEntrada, -4);
    Q.ParamByName('VALORCM').AsFloat := NovoCM;
    Q.ParamByName('DATAUC').AsDate := DataNota;
    Q.ParamByName('PRO').AsInteger := CodPro;
    Q.ExecSQL;

    CodHis := GerarProximoGen(Conn, Trans, 'GEN_HP');
    Q.Close;
    Q.SQL.Text :=
      'INSERT INTO HIS_PRO (' +
      '  HP_CODIGO, HP_DATA, HP_PRO, HP_ORIGEM, HP_DOC, HP_QUANTIDADE, ' +
      '  HP_VALORC, HP_VALORV, HP_VALORCM, HP_VALOROP, HP_VALORM, HP_TIPO, HP_TIPO2, HP_QUANTIDADEA' +
      ') VALUES (' +
      '  :CODIGO, :DATA, :PRO, :ORIGEM, :DOC, :QTD, ' +
      '  :VALORC, :VALORV, :VALORCM, :VALOROP, :VALORM, ''E'', 1, :QTDA' +
      ')';
    Q.ParamByName('CODIGO').AsInteger := CodHis;
    Q.ParamByName('DATA').AsDate := Date;
    Q.ParamByName('PRO').AsInteger := CodPro;
    Q.ParamByName('ORIGEM').AsString := Copy(Trim(Origem), 1, 30);
    Q.ParamByName('DOC').AsString := Copy(Trim(Doc), 1, 15);
    Q.ParamByName('QTD').AsFloat := RoundTo(QtdEntrada, -2);
    Q.ParamByName('VALORC').AsFloat := RoundTo(CustoUnitEntrada, -2);
    Q.ParamByName('VALORV').AsFloat := RoundTo(ValorV, -2);
    Q.ParamByName('VALORCM').AsFloat := RoundTo(NovoCM, -2);
    Q.ParamByName('VALOROP').AsFloat := RoundTo(ValorL, -2);
    Q.ParamByName('VALORM').AsFloat := RoundTo(ValorF, -2);
    Q.ParamByName('QTDA').AsFloat := RoundTo(QtdAtual, -2);
    Q.ExecSQL;
  finally
    Q.DisposeOf;
  end;
end;

class function TProducaoService.BaixarInsumosECalcularCusto(Conn: TFDConnection; Trans: TFDTransaction; const TipoAlvo: string; CodAlvo: Integer; QtdVendida: Double; CodVenda: Integer; out UsouFicha: Boolean; Depth: Integer; Visitados: TDictionary<string, Boolean>): Double;
var
  CreatedDict: Boolean;
  Chave: string;
  Q, QPro, QHis: TFDQuery;
  CodFT: Integer;
  Rendimento, Perda, RendimentoEfetivo, FatorLote, CustoIndireto, CustoUnitFicha: Double;
  CodInsumo: Integer;
  QtdItem, FatorBase, QtdConsumida, CustoUnitInsumo, SubCusto: Double;
  UnidadeItem, UnidadeBase, EstoqueFlag: string;
  QtdAtual, ValorV, ValorC, ValorCM, ValorL, ValorF: Double;
  CodHis: Integer;
  SubUsouFicha: Boolean;
begin
  Result := 0;
  UsouFicha := False;
  if (CodAlvo <= 0) or (QtdVendida <= 0) then
    Exit;

  Chave := UpperCase(Trim(TipoAlvo)) + ':' + CodAlvo.ToString;
  CreatedDict := Visitados = nil;
  if CreatedDict then
    Visitados := TDictionary<string, Boolean>.Create;

  Q := TFDQuery.Create(nil);
  QPro := TFDQuery.Create(nil);
  QHis := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Transaction := Trans;
    QPro.Connection := Conn;
    QPro.Transaction := Trans;
    QHis.Connection := Conn;
    QHis.Transaction := Trans;

    if (Depth >= 8) or Visitados.ContainsKey(Chave) then
      Exit;

    if TabelaExiste(Conn, Trans, 'FICHA_TECNICA') then
    begin
      Q.SQL.Text :=
        'SELECT FIRST 1 FT_CODIGO, FT_RENDIMENTO, FT_PERDA_PERC, FT_CUSTO_INDIRETO, FT_CUSTO_UNIT ' +
        'FROM FICHA_TECNICA ' +
        'WHERE UPPER(TRIM(FT_TIPO_ALVO)) = :TIPO AND FT_COD_ALVO = :ALVO AND COALESCE(FT_ATIVO, ''S'') = ''S'' ' +
        'ORDER BY FT_CODIGO DESC';
      Q.ParamByName('TIPO').AsString := UpperCase(Trim(TipoAlvo));
      Q.ParamByName('ALVO').AsInteger := CodAlvo;
      Q.Open;
    end;

    if (not Q.Active) or Q.IsEmpty then
    begin
      // Sem ficha tecnica ativa: se for PRODUTO retorna custo cadastrado; se OPCAO/ADICIONAL retorna 0
      if UpperCase(Trim(TipoAlvo)) = 'PRODUTO' then
      begin
        QPro.SQL.Text := 'SELECT COALESCE(NULLIF(PRO_VALORCM, 0), PRO_VALORC, 0) AS CUSTO FROM PRODUTOS WHERE PRO_CODIGO = :PRO';
        QPro.ParamByName('PRO').AsInteger := CodAlvo;
        QPro.Open;
        if not QPro.IsEmpty then
          Result := RoundTo(QPro.FieldByName('CUSTO').AsFloat * QtdVendida, -4);
      end;
      Exit;
    end;

    UsouFicha := True;
    Visitados.Add(Chave, True);

    CodFT := Q.FieldByName('FT_CODIGO').AsInteger;
    Rendimento := Q.FieldByName('FT_RENDIMENTO').AsFloat;
    Perda := Q.FieldByName('FT_PERDA_PERC').AsFloat;
    CustoIndireto := Q.FieldByName('FT_CUSTO_INDIRETO').AsFloat;
    CustoUnitFicha := Q.FieldByName('FT_CUSTO_UNIT').AsFloat;
    if Rendimento <= 0 then Rendimento := 1.0;
    if Perda < 0 then Perda := 0 else if Perda > 95 then Perda := 95;
    RendimentoEfetivo := Max(0.0001, Rendimento * (1.0 - (Perda / 100.0)));
    FatorLote := QtdVendida / RendimentoEfetivo;

    Result := RoundTo(CustoIndireto * FatorLote, -4);

    Q.Close;
    Q.SQL.Text :=
      'SELECT I.FTI_PRO_INSUMO, I.FTI_QUANTIDADE, I.FTI_UNIDADE, I.FTI_FATOR_BASE, ' +
      '       COALESCE(NULLIF(P.PRO_VALORCM, 0), P.PRO_VALORC, 0) AS CUSTO_BASE, ' +
      '       COALESCE(P.PRO_EMBALAGEM, '''') AS UNIDADE_BASE ' +
      'FROM FICHA_TECNICA_ITENS I ' +
      'JOIN PRODUTOS P ON P.PRO_CODIGO = I.FTI_PRO_INSUMO ' +
      'WHERE I.FTI_FT = :FT';
    Q.ParamByName('FT').AsInteger := CodFT;
    Q.Open;

    while not Q.Eof do
    begin
      CodInsumo := Q.FieldByName('FTI_PRO_INSUMO').AsInteger;
      QtdItem := Q.FieldByName('FTI_QUANTIDADE').AsFloat;
      UnidadeItem := Q.FieldByName('FTI_UNIDADE').AsString;
      FatorBase := Q.FieldByName('FTI_FATOR_BASE').AsFloat;
      UnidadeBase := Q.FieldByName('UNIDADE_BASE').AsString;
      CustoUnitInsumo := Q.FieldByName('CUSTO_BASE').AsFloat;

      if FatorBase <= 0 then
        FatorBase := CalcularFatorConversao(UnidadeItem, UnidadeBase);

      QtdConsumida := QtdItem * FatorBase * FatorLote;
      if QtdConsumida > 0 then
      begin
        // Verifica se este insumo eh uma sub-receita (produto PRODUCAO com ficha tecnica ativa)
        SubUsouFicha := False;
        SubCusto := BaixarInsumosECalcularCusto(
          Conn, Trans, 'PRODUTO', CodInsumo, QtdConsumida, CodVenda,
          SubUsouFicha, Depth + 1, Visitados
        );

        if SubUsouFicha then
        begin
          Result := Result + SubCusto;
        end
        else
        begin
          Result := Result + (QtdConsumida * CustoUnitInsumo);

          // Baixa fisica do insumo MP/simples
          QPro.Close;
          QPro.SQL.Text :=
            'SELECT COALESCE(PRO_QUANTIDADE, 0) PRO_QUANTIDADE, COALESCE(PRO_ESTOQUE, ''S'') PRO_ESTOQUE, ' +
            '       COALESCE(PRO_VALORC, 0) PRO_VALORC, COALESCE(PRO_VALORCM, 0) PRO_VALORCM, ' +
            '       COALESCE(PRO_VALORV, 0) PRO_VALORV, COALESCE(PRO_VALORL, 0) PRO_VALORL, COALESCE(PRO_VALORF, 0) PRO_VALORF ' +
            'FROM PRODUTOS WHERE PRO_CODIGO = :PRO';
          QPro.ParamByName('PRO').AsInteger := CodInsumo;
          QPro.Open;
          if not QPro.IsEmpty then
          begin
            EstoqueFlag := UpperCase(Trim(QPro.FieldByName('PRO_ESTOQUE').AsString));
            if not EstoqueFlag.Contains('N') then
            begin
              QtdAtual := QPro.FieldByName('PRO_QUANTIDADE').AsFloat;
              ValorC := QPro.FieldByName('PRO_VALORC').AsFloat;
              ValorCM := QPro.FieldByName('PRO_VALORCM').AsFloat;
              ValorV := QPro.FieldByName('PRO_VALORV').AsFloat;
              ValorL := QPro.FieldByName('PRO_VALORL').AsFloat;
              ValorF := QPro.FieldByName('PRO_VALORF').AsFloat;

              QHis.Close;
              QHis.SQL.Text := 'UPDATE PRODUTOS SET PRO_QUANTIDADE = COALESCE(PRO_QUANTIDADE, 0) - :QTD WHERE PRO_CODIGO = :PRO';
              QHis.ParamByName('QTD').AsFloat := QtdConsumida;
              QHis.ParamByName('PRO').AsInteger := CodInsumo;
              QHis.ExecSQL;

              CodHis := GerarProximoGen(Conn, Trans, 'GEN_HP');
              QHis.Close;
              QHis.SQL.Text :=
                'INSERT INTO HIS_PRO (' +
                '  HP_CODIGO, HP_DATA, HP_PRO, HP_ORIGEM, HP_DOC, HP_QUANTIDADE, ' +
                '  HP_VALORC, HP_VALORV, HP_VALORCM, HP_VALOROP, HP_VALORM, HP_TIPO, HP_TIPO2, HP_QUANTIDADEA' +
                ') VALUES (' +
                '  :CODIGO, CURRENT_DATE, :PRO, :ORIGEM, :DOC, :QTD, ' +
                '  :VALORC, :VALORV, :VALORCM, :VALOROP, :VALORM, ''S'', 1, :QTDA' +
                ')';
              QHis.ParamByName('CODIGO').AsInteger := CodHis;
              QHis.ParamByName('PRO').AsInteger := CodInsumo;
              QHis.ParamByName('ORIGEM').AsString := Copy('PROD - VD #' + CodVenda.ToString, 1, 30);
              QHis.ParamByName('DOC').AsString := Copy(CodVenda.ToString, 1, 15);
              QHis.ParamByName('QTD').AsFloat := RoundTo(QtdConsumida, -2);
              QHis.ParamByName('VALORC').AsFloat := RoundTo(ValorC, -2);
              QHis.ParamByName('VALORV').AsFloat := RoundTo(ValorV, -2);
              QHis.ParamByName('VALORCM').AsFloat := RoundTo(ValorCM, -2);
              QHis.ParamByName('VALOROP').AsFloat := RoundTo(ValorL, -2);
              QHis.ParamByName('VALORM').AsFloat := RoundTo(ValorF, -2);
              QHis.ParamByName('QTDA').AsFloat := RoundTo(QtdAtual, -2);
              QHis.ExecSQL;
            end;
          end;
        end;
      end;
      Q.Next;
    end;

    // Fallback se a ficha nao tiver itens mas tiver custo unitario gravado
    if (Result <= 0) and (CustoUnitFicha > 0) then
      Result := RoundTo(CustoUnitFicha * QtdVendida, -4)
    else
      Result := RoundTo(Result, -4);

    Visitados.Remove(Chave);
  finally
    Q.DisposeOf;
    QPro.DisposeOf;
    QHis.DisposeOf;
    if CreatedDict then
      Visitados.Free;
  end;
end;

end.
