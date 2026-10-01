unit Produtos.Admin.Controller;

interface

uses
  Horse,
  Horse.Commons,
  System.JSON;

type
  TProdutosAdminController = class
  public
    class procedure Registrar;
    class procedure PostProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure PutProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure DeleteProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure GetImagemProduto(Req: THorseRequest; Res: THorseResponse);
    class procedure GetImagemCategoria(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

uses
  System.SysUtils,
  UnitDatabase,
  UnitConnection.Model.Interfaces,
  UnitFunctions,
  UnitProdutos.Model,
  UnitTabela.Helpers;

class procedure TProdutosAdminController.GetImagemProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SELECT PRO_CAMINHO_IMAGEM FROM PRODUTOS WHERE PRO_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Req.Params.Items['codigo'].ToInteger);
  Query.Open;
  Res.Send<TJSONObject>(
    TJSONObject.Create.AddPair('imagem', Query.DataSet.FieldByName('PRO_CAMINHO_IMAGEM').AsString)
  );
end;

class procedure TProdutosAdminController.GetImagemCategoria(Req: THorseRequest;
  Res: THorseResponse);
var
  Query: iQuery;
begin
  Query := TDatabase.Query;
  Query.Add('SELECT GRU_CAMINHO_IMAGEM FROM GRUPOS WHERE GRU_CODIGO = :CODIGO');
  Query.AddParam('CODIGO', Req.Params.Items['codigo'].ToInteger);
  Query.Open;
  Res.Send<TJSONObject>(
    TJSONObject.Create.AddPair('imagem', Query.DataSet.FieldByName('GRU_CAMINHO_IMAGEM').AsString)
  );
end;

class procedure TProdutosAdminController.PostProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
  Body: TJSONObject;
  Texto: string;
  Numero: Double;
  Inteiro: Integer;
begin
  Body := Req.Body<TJSONObject>;
  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.CriaTabela;
    Produto.Codigo := GeraCodigo('PRODUTOS', 'PRO_CODIGO');
    Produto.Estado := 'ATIVO';

    if Body.TryGetValue<string>('nome', Texto) then Produto.Nome := Texto;
    if Body.TryGetValue<Double>('valorv', Numero) then Produto.Valorv := Numero;
    if Body.TryGetValue<string>('descricao', Texto) then Produto.Descricao := Texto;
    if Body.TryGetValue<Integer>('gru', Inteiro) then Produto.Gru := Inteiro;
    if Body.TryGetValue<string>('estado', Texto) then Produto.Estado := Texto;
    if Body.TryGetValue<string>('codbarra', Texto) then Produto.Codbarra := Texto;
    if Body.TryGetValue<string>('caminho_imagem', Texto) then Produto.Caminho_imagem := Texto;

    if Produto.Nome.Trim.IsEmpty then
      raise Exception.Create('Nome do produto e obrigatorio.');
    if Produto.Gru <= 0 then
      raise Exception.Create('Grupo do produto e obrigatorio.');

    Produto.SalvaNoBanco(1);
    Res.Status(THTTPStatus.Created).Send<TJSONObject>(Produto.ToJsonObject);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.PutProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
  Body: TJSONObject;
  Codigo, Inteiro: Integer;
  Texto: string;
  Numero: Double;
begin
  Body := Req.Body<TJSONObject>;
  if not Body.TryGetValue<Integer>('codigo', Codigo) then
    raise Exception.Create('Codigo do produto e obrigatorio.');

  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.CriaTabela;
    Produto.BuscaDadosTabela(Codigo);

    if Body.TryGetValue<string>('nome', Texto) then Produto.Nome := Texto;
    if Body.TryGetValue<Double>('valorv', Numero) then Produto.Valorv := Numero;
    if Body.TryGetValue<string>('descricao', Texto) then Produto.Descricao := Texto;
    if Body.TryGetValue<Integer>('gru', Inteiro) then Produto.Gru := Inteiro;
    if Body.TryGetValue<string>('estado', Texto) then Produto.Estado := Texto;
    if Body.TryGetValue<string>('codbarra', Texto) then Produto.Codbarra := Texto;
    if Body.TryGetValue<string>('caminho_imagem', Texto) then Produto.Caminho_imagem := Texto;

    Produto.SalvaNoBanco(1);
    Res.Send<TJSONObject>(Produto.ToJsonObject);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.DeleteProduto(Req: THorseRequest;
  Res: THorseResponse);
var
  Produto: TProdutos;
begin
  Produto := TProdutos.Create(TDatabase.Connection);
  try
    Produto.Apagar(Req.Params.Items['codigo'].ToInteger);
    Res.Send('').Status(THTTPStatus.NoContent);
  finally
    Produto.DisposeOf;
  end;
end;

class procedure TProdutosAdminController.Registrar;
begin
  THorse.Post('/v1/produtos', PostProduto);
  THorse.Put('/v1/produtos', PutProduto);
  THorse.Delete('/v1/produtos/:codigo', DeleteProduto);
  THorse.Get('/v1/produtos/:codigo/imagem', GetImagemProduto);
  THorse.Get('/v1/categorias/:codigo/imagem', GetImagemCategoria);
end;

end.
