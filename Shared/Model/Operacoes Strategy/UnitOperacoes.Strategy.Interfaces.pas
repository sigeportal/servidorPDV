unit UnitOperacoes.Strategy.Interfaces;

interface

uses
	UnitPedFat.Model, 
  UnitPF_Parcela.Model;
  
type
  {$SCOPEDENUMS ON}
  TTipoFatura = (Vista = 1, PrazoComEntrada, Prazo);
  TTipoDescontoCartao = (DescontoRecebimento, Despesa);
  {$SCOPEDENUMS OFF}

  type
  TSubDespesa = record
    Codigo: integer;
    Nome: string;
    Valor: Currency;
  end;

  iOperacoesStrategy  = interface
    ['{8D8F5E67-1B0C-40AA-B472-079491DCBAD2}']
    function SetPF_Parcela(Value: TPF_Parcela): iOperacoesStrategy;
    function SetPed_Fat(Value: TPedFat): iOperacoesStrategy;
    function SetTipoFatura(Value: TTipoFatura): iOperacoesStrategy;
    function SetTipoDescontoCartao(Value: TTipoDescontoCartao): iOperacoesStrategy;
    function SetOperacao(Value: TObject): iOperacoesStrategy;
    function SetItens(Value: TObject): iOperacoesStrategy;
    function InsereOperacao: iOperacoesStrategy;
    function InsereItens: iOperacoesStrategy;
    function InserePedFat: iOperacoesStrategy;
    function InserePFParcela: iOperacoesStrategy;
    function InsereFaturamento: iOperacoesStrategy;
    function SetPercentualJuros(Value: Double): iOperacoesStrategy;
    function CodigoDAV: integer;
  end;


implementation

end.
