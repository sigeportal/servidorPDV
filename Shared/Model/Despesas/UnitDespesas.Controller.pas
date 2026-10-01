unit UnitDespesas.Controller;

interface

uses
  Horse,
  Horse.Commons,
  Horse.GBSwagger,
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  UnitConnection.Model.Interfaces;

type
  TDespesasController = class
  private
    class function SuccessResponse(AData: TJSONValue; const AMessage: string = ''): TJSONObject; static;
    class function ErrorResponse(const AMessage, ACode: string; const ADetails: string = ''): TJSONObject; static;
    class function Query(Connection: TFDConnection; Transaction: TFDTransaction): TFDQuery; static;
    class function ObterCaixa(Connection: TFDConnection; Transaction: TFDTransaction; PDV: Integer): Integer; static;
    class procedure InserirMovimentacao(Connection: TFDConnection; Transaction: TFDTransaction;
      Codigo: Integer; Credito, Debito: Currency; const Descricao, Plano, Nome: string;
      Conta, Caixa, PDV: Integer; Estado: string = 'A'); static;
  public
    class procedure Router;
    class procedure GetSubDespesas(Req: THorseRequest; Res: THorseResponse);
    class procedure Post(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

uses
  UnitDatabase,
  UnitTabela.Helpers,
  UnitDespesas.Model,
  UnitFunctions;

class function TDespesasController.SuccessResponse(AData: TJSONValue; const AMessage: string): TJSONObject;
var
  Meta: TJSONObject;
begin
  Result := TJSONObject.Create;
  Meta := TJSONObject.Create;
  Meta.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));

  Result.AddPair('success', TJSONBool.Create(True));
  Result.AddPair('message', AMessage);
  if Assigned(AData) then
    Result.AddPair('data', AData)
  else
    Result.AddPair('data', TJSONNull.Create);
  Result.AddPair('meta', Meta);
end;

class function TDespesasController.ErrorResponse(const AMessage, ACode, ADetails: string): TJSONObject;
var
  ErrorObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  ErrorObj := TJSONObject.Create;
  ErrorObj.AddPair('code', ACode);
  if not ADetails.IsEmpty then
    ErrorObj.AddPair('details', ADetails)
  else
    ErrorObj.AddPair('details', TJSONNull.Create);
  ErrorObj.AddPair('fields', TJSONArray.Create);

  Result.AddPair('success', TJSONBool.Create(False));
  Result.AddPair('message', AMessage);
  Result.AddPair('error', ErrorObj);
end;

class function TDespesasController.Query(Connection: TFDConnection; Transaction: TFDTransaction): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := Connection;
  Result.Transaction := Transaction;
end;

class function TDespesasController.ObterCaixa(Connection: TFDConnection; Transaction: TFDTransaction; PDV: Integer): Integer;
var
  Q: TFDQuery;
begin
  Q := Query(Connection, Transaction);
  try
    Q.SQL.Add('SELECT FIRST 1 CAI_CODIGO FROM CAIXA');
    Q.SQL.Add('WHERE (:PDV = 0 OR CAI_PDV = :PDV)');
    Q.SQL.Add('ORDER BY CAI_CODIGO DESC');
    Q.ParamByName('PDV').AsInteger := PDV;
    Q.Open;

    if Q.IsEmpty then
      Result := 0
    else
      Result := Q.FieldByName('CAI_CODIGO').AsInteger;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TDespesasController.InserirMovimentacao(Connection: TFDConnection; Transaction: TFDTransaction;
  Codigo: Integer; Credito, Debito: Currency; const Descricao, Plano, Nome: string;
  Conta, Caixa, PDV: Integer; Estado: string);
var
  Q: TFDQuery;
begin
  Q := Query(Connection, Transaction);
  try
    Q.SQL.Add('INSERT INTO MOVIMENTACOES (');
    Q.SQL.Add('  MOV_CODIGO, MOV_CREDITO, MOV_DEBITO, MOV_DESCRICAO, MOV_TIPO, MOV_DATA, MOV_CON,');
    Q.SQL.Add('  MOV_DATAHORA, MOV_ORDENA, MOV_PLANO, MOV_NOME, MOV_CAI, MOV_ESTADO, MOV_TROCO');
    Q.SQL.Add(') VALUES (');
    Q.SQL.Add('  :CODIGO, :CREDITO, :DEBITO, :DESCRICAO, :TIPO, :DATA, :CONTA,');
    Q.SQL.Add('  :DATAHORA, :ORDENA, :PLANO, :NOME, :CAIXA, :ESTADO, 0');
    Q.SQL.Add(')');
    Q.ParamByName('CODIGO').AsInteger := Codigo;
    Q.ParamByName('CREDITO').AsCurrency := Credito;
    Q.ParamByName('DEBITO').AsCurrency := Debito;
    Q.ParamByName('DESCRICAO').AsString := Copy(Descricao, 1, 30);
    Q.ParamByName('TIPO').AsInteger := 2;
    Q.ParamByName('DATA').AsDate := Date;
    Q.ParamByName('CONTA').AsInteger := Conta;
    Q.ParamByName('DATAHORA').AsDateTime := Now;
    Q.ParamByName('ORDENA').AsInteger := Codigo;
    Q.ParamByName('PLANO').AsString := Plano;
    Q.ParamByName('NOME').AsString := Copy(Nome, 1, 30);
    Q.ParamByName('CAIXA').AsInteger := Caixa;
    Q.ParamByName('ESTADO').AsString := Estado;
    Q.ExecSQL;

    Q.SQL.Clear;
    if Conta = 0 then
    begin
      Q.SQL.Add('UPDATE CAIXA SET CAI_VALORD = COALESCE(CAI_VALORD, 0) + :CREDITO - :DEBITO');
      Q.SQL.Add('WHERE CAI_CODIGO = :CODIGO');
      Q.ParamByName('CODIGO').AsInteger := Caixa;
    end
    else
    begin
      Q.SQL.Add('UPDATE CONTAS SET CON_SALDO = COALESCE(CON_SALDO, 0) + :CREDITO - :DEBITO');
      Q.SQL.Add('WHERE CON_CODIGO = :CODIGO');
      Q.ParamByName('CODIGO').AsInteger := Conta;
    end;
    Q.ParamByName('CREDITO').AsCurrency := Credito;
    Q.ParamByName('DEBITO').AsCurrency := Debito;
    Q.ExecSQL;
  finally
    Q.DisposeOf;
  end;
end;

class procedure TDespesasController.Post(Req: THorseRequest; Res: THorseResponse);
var
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Transacao: TFDTransaction;
  Despesa: TDespesaLancamento;
  Q: TFDQuery;
  CodFat2, CodCusto, CodPag, CodMov, CodPP: Integer;
  DataObj: TJSONObject;
begin
  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Transacao := TFDTransaction.Create(nil);
  Despesa := nil;

  try
    try
      Transacao.Connection := Conexao;
      Despesa := TDespesaLancamento.Create(Conexao, Transacao).fromJson<TDespesaLancamento>(Req.Body);

      if Despesa.SubDespesa <= 0 then
      begin
        Res.Status(THTTPStatus.BadRequest)
          .Send<TJSONObject>(ErrorResponse('SubDespesa e obrigatoria.', 'VALIDATION_ERROR'));
        Exit;
      end;

      if Despesa.Valor <= 0 then
      begin
        Res.Status(THTTPStatus.BadRequest)
          .Send<TJSONObject>(ErrorResponse('Valor deve ser maior que zero.', 'VALIDATION_ERROR'));
        Exit;
      end;

      if Despesa.PDV <= 0 then
        Despesa.PDV := 1;
      if Despesa.Data <= 0 then
        Despesa.Data := Date;
      if Despesa.Historico.IsEmpty then
        Despesa.Historico := 'LANCAMENTO DE DESP';
      if Despesa.Documento.IsEmpty then
        Despesa.Documento := Despesa.SubDespesa.ToString;
      if Despesa.TipoPagamento.IsEmpty then
        Despesa.TipoPagamento := 'DINHEIRO';

      Transacao.StartTransaction;
      try
      if Despesa.SubDespesaNome.IsEmpty then
      begin
        Q := Query(Conexao, Transacao);
        try
          Q.SQL.Add('SELECT SUD_NOME FROM SUB_DES WHERE SUD_CODIGO = :CODIGO');
          Q.ParamByName('CODIGO').AsInteger := Despesa.SubDespesa;
          Q.Open;
          if not Q.IsEmpty then
            Despesa.SubDespesaNome := Q.FieldByName('SUD_NOME').AsString;
        finally
          Q.DisposeOf;
        end;
      end;
      Despesa.Caixa := ObterCaixa(Conexao, Transacao, Despesa.PDV);
      CodFat2 := IncrementaGenerator('GEN_FAT2');
      CodCusto := IncrementaGenerator('GEN_CUST');
      CodPag := IncrementaGenerator('GEN_PAG');
      CodMov := IncrementaGenerator('GEN_MOV');
      CodPP := IncrementaGenerator('GEN_PP');

      Q := Query(Conexao, Transacao);
      try
        Q.SQL.Add('INSERT INTO CUSTOS (');
        Q.SQL.Add('  CUST_CODIGO, CUST_DATA, CUST_NDOC, CUST_HISTORICO, CUST_SUD, CUST_VALOR,');
        Q.SQL.Add('  CUST_FUN, CUST_DATAC, CUST_FAT2, CUST_TIPO, CUST_COD_FUN, CUST_COD_FOR');
        Q.SQL.Add(') VALUES (');
        Q.SQL.Add('  :CODIGO, :DATA, :NDOC, :HISTORICO, :SUD, :VALOR,');
        Q.SQL.Add('  :FUN, :DATAC, :FAT2, :TIPO, :COD_FUN, :COD_FOR');
        Q.SQL.Add(')');
        Q.ParamByName('CODIGO').AsInteger := CodCusto;
        Q.ParamByName('DATA').AsDate := Despesa.Data;
        Q.ParamByName('NDOC').AsString := Copy(Despesa.Documento, 1, 50);
        Q.ParamByName('HISTORICO').AsString := Copy(Despesa.Historico, 1, 50);
        Q.ParamByName('SUD').AsInteger := Despesa.SubDespesa;
        Q.ParamByName('VALOR').AsCurrency := Despesa.Valor;
        Q.ParamByName('FUN').AsInteger := Despesa.Funcionario;
        Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
        Q.ParamByName('FAT2').AsInteger := CodFat2;
        Q.ParamByName('TIPO').AsString := 'D';
        Q.ParamByName('COD_FUN').AsInteger := 0;
        Q.ParamByName('COD_FOR').AsInteger := 0;
        Q.ExecSQL;
      finally
        Q.DisposeOf;
      end;

      Q := Query(Conexao, Transacao);
      try
        Q.SQL.Add('INSERT INTO FATURAMENTO2 (');
        Q.SQL.Add('  FAT2_CODIGO, FAT2_TIPO, FAT2_VALOR, FAT2_DESCRICAO, FAT2_TIPOPGM, FAT2_PARCELAS, FAT2_JUROS, FAT2_DATA');
        Q.SQL.Add(') VALUES (');
        Q.SQL.Add('  :CODIGO, 2, :VALOR, :DESCRICAO, 1, 1, 0, :DATA');
        Q.SQL.Add(')');
        Q.ParamByName('CODIGO').AsInteger := CodFat2;
        Q.ParamByName('VALOR').AsCurrency := Despesa.Valor;
        Q.ParamByName('DESCRICAO').AsInteger := CodCusto;
        Q.ParamByName('DATA').AsDate := Despesa.Data;
        Q.ExecSQL;
      finally
        Q.DisposeOf;
      end;

      Q := Query(Conexao, Transacao);
      try
        Q.SQL.Add('INSERT INTO PAGAMENTOS (');
        Q.SQL.Add('  PAG_CODIGO, PAG_VALOR, PAG_VENCIMENTO, PAG_JUROS, PAG_ESTADO, PAG_DUPLICATA, PAG_FPG,');
        Q.SQL.Add('  PAG_FAT2, PAG_DESCONTOS, PAG_CAI, PAG_TIPO, PAG_SITUACAO, PAG_OBS, PAG_CON, PAG_DATAC');
        Q.SQL.Add(') VALUES (');
        Q.SQL.Add('  :CODIGO, :VALOR, :VENCIMENTO, 0, 3, :DUPLICATA, 1,');
        Q.SQL.Add('  :FAT2, 0, :CAIXA, :TIPO, 0, :OBS, -1, :DATAC');
        Q.SQL.Add(')');
        Q.ParamByName('CODIGO').AsInteger := CodPag;
        Q.ParamByName('VALOR').AsCurrency := Despesa.Valor;
        Q.ParamByName('VENCIMENTO').AsDate := Despesa.Data;
        Q.ParamByName('DUPLICATA').AsString := CodFat2.ToString + '-1/1';
        Q.ParamByName('FAT2').AsInteger := CodFat2;
        Q.ParamByName('CAIXA').AsInteger := Despesa.Caixa;
        Q.ParamByName('TIPO').AsString := Copy(Despesa.TipoPagamento, 1, 20);
        Q.ParamByName('OBS').AsString := Copy(Despesa.Historico, 1, 100);
        Q.ParamByName('DATAC').AsDate := EncodeDate(1900, 1, 1);
        Q.ExecSQL;
      finally
        Q.DisposeOf;
      end;

      InserirMovimentacao(Conexao, Transacao, CodMov, 0, Despesa.Valor,
        'DES - ' + Despesa.SubDespesaNome, '2.2', 'DESPESA', 0, Despesa.Caixa, Despesa.PDV);

      Q := Query(Conexao, Transacao);
      try
        Q.SQL.Add('INSERT INTO PAG_PGM (');
        Q.SQL.Add('  PP_CODIGO, PP_DATAPGM, PP_DINHEIRO, PP_CHEQUE, PP_MOV, PP_PAG, PP_HORA, PP_FUN, PP_CAI, PP_JUROS, PP_DESCONTOS');
        Q.SQL.Add(') VALUES (');
        Q.SQL.Add('  :CODIGO, :DATAPGM, :DINHEIRO, 0, :MOV, :PAG, :HORA, :FUN, :CAIXA, 0, 0');
        Q.SQL.Add(')');
        Q.ParamByName('CODIGO').AsInteger := CodPP;
        Q.ParamByName('DATAPGM').AsDate := Despesa.Data;
        Q.ParamByName('DINHEIRO').AsCurrency := Despesa.Valor;
        Q.ParamByName('MOV').AsInteger := CodMov;
        Q.ParamByName('PAG').AsInteger := CodPag;
        Q.ParamByName('HORA').AsTime := Time;
        Q.ParamByName('FUN').AsInteger := Despesa.Funcionario;
        Q.ParamByName('CAIXA').AsInteger := Despesa.Caixa;
        Q.ExecSQL;
      finally
        Q.DisposeOf;
      end;

      if Despesa.Conta > 0 then
      begin
        InserirMovimentacao(Conexao, Transacao, IncrementaGenerator('GEN_MOV'), Despesa.Valor, 0,
          'TR - ' + Despesa.SubDespesaNome, '5.4', 'TRANSFERENCIA', 0, Despesa.Caixa, Despesa.PDV, 'B');
        InserirMovimentacao(Conexao, Transacao, IncrementaGenerator('GEN_MOV'), 0, Despesa.Valor,
          'DES - ' + Despesa.SubDespesaNome, '2.2', 'DESPESA', Despesa.Conta, Despesa.Caixa, Despesa.PDV, 'B');
      end;

      Transacao.Commit;

      Despesa.Codigo := CodCusto;
      Despesa.Fatura2 := CodFat2;
      Despesa.Pagamento := CodPag;
      Despesa.Movimentacao := CodMov;

      DataObj := Despesa.ToJsonObject;
      Res.Status(THTTPStatus.Created)
        .Send<TJSONObject>(SuccessResponse(DataObj, 'Despesa lancada com sucesso.'));
      except
        if Transacao.Active then
          Transacao.Rollback;
        raise;
      end;
    except
      on E: Exception do
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao lancar despesa.', 'INTERNAL_ERROR', E.Message));
    end;
  finally
    if Assigned(Despesa) then
      Despesa.DisposeOf;
    Transacao.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
  end;
end;

class procedure TDespesasController.GetSubDespesas(Req: THorseRequest; Res: THorseResponse);
var
  BancoDados: iConnection;
  IndiceConexao: Integer;
  Conexao: TFDConnection;
  Q: TFDQuery;
  Busca: string;
  Lista: TJSONArray;
  Item: TJSONObject;
begin
  Q := nil;
  Lista := nil;
  BancoDados := TDatabase.Connection;
  IndiceConexao := BancoDados.Connected;
  Conexao := TFDConnection(BancoDados.GetListaConexoes[IndiceConexao]);
  Lista := TJSONArray.Create;
  Q := TFDQuery.Create(nil);
  try
    try
      Busca := '';
      if Req.Query.ContainsKey('busca') then
        Busca := UpperCase(Trim(Req.Query.Items['busca']));

      Q.Connection := Conexao;
      Q.SQL.Add('SELECT FIRST 100 SUD_CODIGO, SUD_NOME FROM SUB_DES');
      if not Busca.IsEmpty then
      begin
        Q.SQL.Add('WHERE UPPER(SUD_NOME) LIKE :BUSCA');
        Q.ParamByName('BUSCA').AsString := '%' + Busca + '%';
      end;
      Q.SQL.Add('ORDER BY SUD_NOME');
      Q.Open;

      while not Q.Eof do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('codigo', TJSONNumber.Create(Q.FieldByName('SUD_CODIGO').AsInteger));
        Item.AddPair('nome', Q.FieldByName('SUD_NOME').AsString);
        Lista.AddElement(Item);
        Q.Next;
      end;

      Res.Send<TJSONObject>(SuccessResponse(Lista, 'Subdespesas encontradas.'));
      Lista := nil;
    except
      on E: Exception do
        Res.Status(THTTPStatus.InternalServerError)
          .Send<TJSONObject>(ErrorResponse('Falha ao consultar subdespesas.', 'INTERNAL_ERROR', E.Message));
    end;
  finally
    if Assigned(Q) then
      Q.DisposeOf;
    if Assigned(Lista) then
      Lista.DisposeOf;
    BancoDados.Disconnected(IndiceConexao);
  end;
end;

class procedure TDespesasController.Router;
begin
  THorse.Group
    .Prefix('/v1')
    .Route('/despesas/subdespesas')
      .Get(GetSubDespesas)
    .&End
    .Group
        .Prefix('/v1')
    .Route('/despesas')
      .Post(Post)
    .&End
end;

initialization
  Swagger
    .Path('despesas/subdespesas')
      .Tag('Despesas')
      .GET('Lista Subdespesas', 'Lista subdespesas por nome para selecao no lancamento')
        .AddResponse(200, 'Operacao bem sucedida').&End
        .AddResponse(500).&End
      .&End
    .&End
    .Path('despesas')
      .Tag('Despesas')
      .POST('Lancar Despesa', 'Registra uma despesa com faturamento, pagamento e movimentacao de caixa')
        .AddParamBody('Dados da despesa', 'Despesa')
          .Required(True)
          .Schema(TDespesaLancamento)
        .&End
        .AddResponse(201, 'Created')
          .Schema(TDespesaLancamento)
        .&End
        .AddResponse(400, 'BadRequest').&End
        .AddResponse(500).&End
      .&End
    .&End
  .&End;

end.
